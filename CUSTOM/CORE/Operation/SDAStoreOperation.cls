Include (%ZHSLIB, HS.Common)

Class CUSTOM.CORE.Operation.SDAStoreOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

// Parameter SETTINGS As %String = "TraceOperations:Dev:selector?Select=1&context={HS.Util.ContextSearch/TraceValues},-FailureTimeout,SearchTimeout,ServiceRegistry";

/// Settings for this Business Process
Parameter SETTINGS As %String;

/// Timeout for waiting for a response from the AG.
Property SearchTimeout As %Integer [ InitialExpression = 15 ];

/// Service registry entry correlating to the target AG endpoint to access SearchAndFetchGeneral on.
Property ServiceRegistry As %String;

/// Returns a requested SDA filtered according to input parameters.
Method SendSDA(pRequest As CUSTOM.Util.Message.InboundSDARequest, Output pResponse As CUSTOM.Util.Message.InboundSDAResponse) As %Status
{
	//==Init==
	set tSC=$$$OK
	set pResponse=##class(CUSTOM.Util.Message.InboundSDAResponse).%New()
	
	try {
		//////////////////////////
		//Find service registry EG name
		set tEGServiceRegistryEntryName=""
		set tFacilityCode=pRequest.TargetFacilityCode
		&SQL(SELECT gw.Name INTO :tEGServiceRegistryEntryName
				FROM HS_Facility.Config f, HS_Gateway.Config gw
				WHERE f.FacilityCode=:tFacilityCode AND f.Gateway=gw.ID)
		if SQLCODE=100 {
			//Not found
			set tSC=$$$ERROR($$$GeneralError,"No Facility Service Regisry entry for '"_tFacilityCode_"' found.")
			quit
		} elseif (SQLCODE'=0) {
			//Error
			set tSC=$$$ERROR($$$GeneralError,"SQL Error occured retrieving Facility Service Regisry entry for '"_tFacilityCode_"'. SQL CODE:"_SQLCODE)
			quit
		}
		
		//tEGServiceRegistryEntryName
		if tEGServiceRegistryEntryName="" {
			set tSC=$$$ERROR($$$GeneralError,"No Facility Service Regisry entry for '"_tFacilityCode_"' found.")
			quit
		}
		
		// Validate input SDA stream
		Set tSDAType=pRequest.ValidateRequiredFields(.tValidationErrorText)
		If tSDAType="" {
			Set pResponse.ErrorStatus=tValidationErrorText
			Set tSC=$$$ERROR($$$GeneralError,tValidationErrorText)
			Quit
		}
		
		//===Build Request===
		//Convert Input SDA Stream to HS.Message.ECRUpdateRequest
		set tECRUpdateRequest=##class(HS.Message.ECRUpdateRequest).%New()
		set tSC=tECRUpdateRequest.ContentStream.CopyFrom(pRequest.SDAContent)
		quit:$$$ISERR(tSC)
		set tECRUpdateRequest.UpdateECRDemographics=1
		set tECRUpdateRequest.QueryCacheUpdate=0
		set tECRUpdateRequest.StreamContentType=tSDAType
		
		//Invoke HS.Gateway.HSWS.WebServicesClient:EPRSave
		#dim tECRUpdateResponse As HS.Message.ECRUpdateResponse
		set tECRUpdateResponse=$$$NULLOREF
		set tSC=..invokeEPRSave(tEGServiceRegistryEntryName,tECRUpdateRequest,.tECRUpdateResponse)

		//Process Response.
		//Re-process any SOAP exceptions into the real error.		
		if '$ISOBJECT(tECRUpdateResponse) {
			set tECRUpdateResponse=##class(HS.Message.ECRUpdateResponse).%New()
			
			//Rework Text for propper soap exceptions
			do $SYSTEM.Status.DecomposeStatus(tSC,.err)
			set tErrorText=err(err)
			kill err
			
			if $EXTRACT(tErrorText,1,60)="ERROR #6248: SOAP response is a SOAP fault: faultcode=Method" {
				//We have a soap exception; pull the error text
				set tErrorTextDesc=$E(tErrorText,$FIND(tErrorText,"<text>"),$FIND(tErrorText,"</text>")-8)
				set tSC=$$$ERROR($$$GeneralError,tErrorTextDesc) //Real error
			} else {
				quit
			}
		}
		if $$$ISERR(tSC) quit

		set pResponse=##class(CUSTOM.Util.Message.InboundSDAResponse).%New()

	} catch(e) {
		//Error
		set tSC=e.AsStatus()
		$$$LOGERROR("Error: "_e.AsStatus())
	}
	if $$$ISERR(tSC) {
		set pResponse.ErrorStatus=$SYSTEM.Status.GetErrorText(tSC)
		set:pResponse.ErrorStatus["XSLT XML Transformer Error: SAXParseException:" pResponse.ErrorStatus="Invalid SDA content: "_pResponse.ErrorStatus
	}
	
	Quit tSC
}

/// Invoke a web service request
Method invokeEPRSave(pServiceRegistryEP As %String, pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status [ Internal, Private ]
{
	Set tSC=$$$OK,$ZT="SOAPTrap"
	$$$HSPerfStart("Invoke "_pMethod)
	
	Set tConfig = ##class(HS.Registry.Service.SOAP).EndPointForNameType(pServiceRegistryEP,"SOAP")
	if (tConfig = "") {
		$$$LOGERROR("Service Registry not configured for Name: "_pServiceRegistryEP)
		$$$ThrowStatus($$$ERROR($$$GeneralError,"Internal Web Service error"))
	}

	Set tClient=##class(HS.Gateway.HSWS.WebServicesClient).%New()
	Set tClient.Location=tConfig.EndPoint
	set tClient.Timeout=..SearchTimeout
	if (tConfig.UsernameTokenProfileConfig '= "") {
		Set tCredentials = ##class(Ens.Config.Credentials).%OpenId(tConfig.UsernameTokenProfileConfig)
		Set tSC=tClient.WSSecurityLogin(tCredentials.Username,tCredentials.Password) 
		If $$$ISERR(tSC) $$$ThrowStatus(tSC)
	}
	Set tClient.SSLConfiguration=tConfig.SSLConfig
	set tSC=tClient.EPRSave(pRequest, .pResponse)
	
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
	<MapItem MessageType="CUSTOM.Util.Message.InboundSDARequest"> 
		<Method>SendSDA</Method>
	</MapItem>
</MapItems>
}

}
