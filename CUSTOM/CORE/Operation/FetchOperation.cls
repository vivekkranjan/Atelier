Include (%ZHSLIB, HS.Common)

Class CUSTOM.CORE.Operation.FetchOperation Extends (Ens.BusinessOperation, HS.Util.Trace.Helper, HS.Util.Trace.Performance)
{

// Removed: NSLIJ prefers not using the adapter but the web service client direction

// Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter";

Parameter INVOCATION = "Queue";

// Removed: NSLIJ prefers not using the adapter but the web service client direction

// /// Web services client class for AG

// Parameter WEBSERVICECLIENTCLASS As %String = "HS.Gateway.HSWS.WebServicesClient";

/// Settings for this Business Process
Parameter SETTINGS As %String = "TraceOperations:Dev:selector?Select=1&context={HS.Util.ContextSearch/TraceValues},-FailureTimeout,SearchTimeout,ServiceRegistry";

/// Timeout for waiting for a response from the AG.
Property SearchTimeout As %Integer [ InitialExpression = 15 ];

/// Service registry entry correlating to the target AG endpoing to access SearchAndFetchGeneral on.
Property ServiceRegistry As %String;

/// Returns a requested SDA filtered according to input parameters.
Method SDAFetch(pRequest As CUSTOM.Util.Message.FetchPatientRequest, Output pResponse As CUSTOM.Util.Message.FetchPatientResponse) As %Status
{
	//==Init==
	set tSC=$$$OK
	set pResponse=##class(CUSTOM.Util.Message.FetchPatientResponse).%New()
	
	try {
		$$$HSTRACE("Search And Fetch General Based Processing","pRequest",pRequest)
		
		//Validations
		if ((pRequest.MRN'="") || (pRequest.AssigningAuthority'="")) {
			if ((pRequest.MRN="") || (pRequest.AssigningAuthority="")) {
				//Validation error; both AA and MRN are required when either are specified.
				set tSC=$$$ERROR($$$GeneralError,"Both AA and MRN are required when either are specified.")
				quit
			}
		}
		
		set tMPIID=pRequest.MPIID
		set tMRN=pRequest.MRN
		set tAssigningAuthority=pRequest.AssigningAuthority
		
		//If EPI was passed find the MPIID
		if ((pRequest.EPI'="") && (pRequest.MPIID="")) {
			//Setup search request to get MPIID
			set tPatientSearchRequest=##class(HS.Message.PatientSearchRequest).%New()
			set tEPIIdentifier=##class(HS.Types.Identifier).%New()
			set tEPIIdentifier.AssigningAuthorityName="EPI"
			set tEPIIdentifier.Extension=pRequest.EPI
			set tEPIIdentifier.Use="XX"
			set tSC=tPatientSearchRequest.Identifiers.Insert(tEPIIdentifier)
			quit:$$$ISERR(tSC)
			set tPatientSearchRequest.SearchMode="admin"
			//GET MPIID
			#dim tPatientSearchResponse As HS.Message.PatientSearchResponse
			set tSC=..SendRequestSync("HUB", tPatientSearchRequest, .tPatientSearchResponse)
			quit:$$$ISERR(tSC)
			if tPatientSearchResponse.MPIIDList.Count() = 0 {
				set tSC=$$$ERROR($$$GeneralError,"Patient not found.")
				quit
			}
			if tPatientSearchResponse.MPIIDList.Count() > 1 {
				set tSC=$$$ERROR($$$GeneralError,"EPI number not unique, associated to more than one patient.")
				quit
			}
			set tMPIID=tPatientSearchResponse.MPIIDList.GetAt(1).MPIID
			set tMRN=""
			set tAssigningAuthority=""
		}
		//////////////////////////
		//===Build Request===
		set tFetchRequest=##class(HS.Message.SearchAndFetchRequest).%New()
		
		//Add info type filters
		for tI=1:1:pRequest.InfoTypes.Count() {
			do tFetchRequest.Filters.InfoTypes.Insert(pRequest.InfoTypes.GetAt(tI))
		}
		
		//Add other selection criteria
		set tFetchRequest.MPIID=tMPIID
		set tFetchRequest.MRN=tMRN
		set tFetchRequest.AssigningAuthority=tAssigningAuthority

		//=====Perform Search and Fetch General against targeted AG.=====
		#dim tFetchResponse As HS.Message.SearchAndFetchResponse
		set tFetchResponse=$$$NULLOREF
		//set tSC=..invokeAccessHSWS("SearchAndFetchGeneral", tFetchRequest, .tFetchResponse, 0,0)
		
		set tSC=..Invoke("SearchAndFetchGeneral", tFetchRequest, .tFetchResponse)
		
		if '$ISOBJECT(tFetchResponse) {
			set tFetchResponse=##class(HS.Message.SearchAndFetchResponse).%New()
			
			//Rework Text for propper soap exceptions
			do $SYSTEM.Status.DecomposeStatus(tSC,.err)
			set tErrorText=err(err)
			kill err
			
			if $EXTRACT(tErrorText,1,60)="ERROR #6248: SOAP response is a SOAP fault: faultcode=Method" {
				//We have a soap exception; pull the error text
				set tErrorTextDesc=$E(tErrorText,$FIND(tErrorText,"<text>"),$FIND(tErrorText,"</text>")-8)
				
				//Known errors which we do not want full blown exceptions for
				//MRNNotFound
				//MPINotFound

				if ($FIND(tErrorTextDesc,"MRNNotFound") || $FIND(tErrorTextDesc,"MPINotFound")) {
					//Patient Not found
					//return response
					set pResponse.PatientFound=0
					set tSC=$$$ERROR($$$GeneralError,"Patient not found.")
					quit
				} else {
					set pResponse.PatientFound=0
					set tSC=$$$ERROR($$$GeneralError,tErrorTextDesc) //Real error
					quit
				}
			} else {
				quit
			}
		} else {
			if tFetchResponse.tStatus'="" {
				if $$$ISERR(tFetchResponse.tStatus) {
					set tSC=tFetchResponse.tStatus
					quit
				}
			}
		}
		if $$$ISERR(tSC) quit
		
		//Get stream
		set tSDAStream=tFetchResponse.XMLData
		
		//==Copy final stream to quickstream==
		set tQuickstream=##class(HS.SDA3.QuickStream).%New()
		set tSC=tQuickstream.CopyFromAndSave(tSDAStream)
		if $$$ISERR(tSC) quit
		
		$$$HSTRACE("Output Quick Stream Size","tQuickstream.Size",tQuickstream.Size)
		
		//done - set qs id for response
		set pResponse.QuickStreamId=tQuickstream.%Id()
		$$$HSTRACE("Current cached quickstream id returned","pResponse.QuickStreamId",pResponse.QuickStreamId)
	} catch(e) {
		//Error
		set tSC=e.AsStatus()
		$$$LOGERROR("Error: "_e.AsStatus())
	}
	set pResponse.Status=tSC
	Quit $$$OK
}

/*
Method invokeAccessHSWS(pMethod As %String, pRequest As Ens.Request, ByRef pResponse As Ens.Response, pMustSend As %Integer = 1, pResponseIsSecondArg As %Boolean = 0) As %Status
{
	quit ..invoke2("HS.Gateway.Access.WebServicesClient",pMethod, ..ServiceRegistry, pRequest, .pResponse, pMustSend,pResponseIsSecondArg)
	//quit ..invoke(pMethod, pRequest, .pResponse)
}

/// similar to invoke, except it expects the response to be a response message rather than a status code.
/// pResponseIsSecondArg handles response=method(request) vs. method(request,.response) calls.
Method invoke2(pWebServiceClientClass As %String, pMethod As %String, pServiceName As %String, pRequest As Ens.Request, ByRef pResponse As Ens.Response, pMustSend As %Integer = 1, pResponseIsSecondArg As %Boolean = 0) As %Status
{
	#dim tSC As %Status
	Set tSC=$$$OK,$ZT="Trap"
	$$$HSPerfStart("Invoke "_pMethod)
	Do {
		Set tEndPoint=""
		//w ##class(%Library.Function).HostName()
		// First step in deprecating TargetName in favor of ServiceName.
		// Let ServiceName override TargetName.
		
		Set pURL=""
		set tEndPoint = ##class(HS.Registry.Service.SOAP).EndPointForNameType(pServiceName,"SOAP")
		
		if '$ISOBJECT(tEndPoint) {
			set tSC=$$$ERROR($$$GeneralError,"Could not retrieve service endpoint for:'"_pServiceName_"'")
			quit
		}
		
		set tURL=tEndPoint.EndPoint
		set ..Adapter.SOAPCredentials=tEndPoint.UsernameTokenProfileConfig
		set ..Adapter.SSLConfig=tEndPoint.SSLConfig
		
		If tURL="" {
			set tSC = $$$HSError($$$HSErrGatewayNotFound,pURL)
			quit
		}

		// Specify the endpoint to connect to
		Set ..Adapter.WebServiceURL = tURL
		Set ..Adapter.WebServiceClientClass = pWebServiceClientClass
		

		$$$HSTRACE("Invoking Request"_pMethod,"pRequest",pRequest)
		//This is the style of invoke
		if (pResponseIsSecondArg) {
			Set tSC = ..Adapter.InvokeMethod(pMethod, .tResultSC, pRequest, .pResponse)
			$$$HSTRACE("Got Response","tResultSC,tSC,pResponse",tResultSC,tSC,pResponse)
		} else {
			Set tSC = ..Adapter.InvokeMethod(pMethod, .pResponse, pRequest)
			$$$HSTRACE("Got Response","pResponse,tSC",pResponse,tSC)
		}

		If $$$ISERR(tSC),pMustSend {
			// Retry if this is a "must send" message.  Actual retry behavior is controlled by the
			// RetryInterval and FailureTimeout operation settings.
			Set ..Retry = 1
		}

		//No status quites so this is not needed.
		// Handle local connection errors and remote errors coming back
		//Set:$$$ISOK(tSC) tSC = tResultSC
		// Handle local connection errors and remote errors coming back
		if (pResponseIsSecondArg) {
			Set:$$$ISOK(tSC) tSC = tResultSC
		}

	} While (0)
Exit
	$$$HSPerfEnd
	Quit tSC
Trap
	Set $ZT="",tSC=$S($ZE["ZSOA":%objlasterror,1:$$$EnsSystemError)
	Goto Exit
}
*/
/// Invoke a web service request
Method Invoke(pMethod As %String, pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status [ Internal, Private ]
{
	Set tSC=$$$OK,$ZT="SOAPTrap"
	$$$HSPerfStart("Invoke "_pMethod)

	Set tConfig = ##class(HS.Registry.Service.SOAP).EndPointForNameType(..ServiceRegistry,"SOAP")
	if (tConfig = "") {
		$$$LOGERROR("Service Registry not configured for Name: "_..ServiceRegistry)
		$$$ThrowStatus($$$ERROR($$$GeneralError,"Internal Web Service error"))
	}

	Set tClient=##class(HS.Gateway.Access.WebServicesClient).%New()
	Set tClient.Location=tConfig.EndPoint
	set tClient.Timeout=..SearchTimeout
	if (tConfig.UsernameTokenProfileConfig '= "") {
		Set tCredentials = ##class(Ens.Config.Credentials).%OpenId(tConfig.UsernameTokenProfileConfig)
		Set tSC=tClient.WSSecurityLogin(tCredentials.Username,tCredentials.Password) 
		If $$$ISERR(tSC) $$$ThrowStatus(tSC)
	}
	Set tClient.SSLConfiguration=tConfig.SSLConfig

	Set pResponse = $METHOD(tClient, pMethod, pRequest)

	
Exit
	$$$HSPerfEnd
	Quit tSC
	
SOAPTrap
	Set $ZT=""
	If ""'=$Get(%objlasterror) {
		Set tSC=%objlasterror
	} Else {
		Set tZE=$ZE,tSC=$$$ERROR($$$GeneralError,$g(tZE)) 
	}
	goto Exit
}

XData MessageMap
{
<MapItems>
	<MapItem MessageType="CUSTOM.Util.Message.FetchPatientRequest"> 
		<Method>SDAFetch</Method>
	</MapItem>
</MapItems>
}

}
