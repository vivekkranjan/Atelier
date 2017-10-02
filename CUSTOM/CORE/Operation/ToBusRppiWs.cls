Class CUSTOM.CORE.Operation.ToBusRppiWs Extends (Ens.BusinessOperation, HS.Util.Trace.Helper, HS.Util.Trace.Performance) [ ProcedureBlock ]
{

/// WebService URL for the Hub
Property HubEndpoint As HS.Types.EndPoint;

/// The configuration item name found in HS.Registry.Service.*
Property ServiceName As %String [ InitialExpression = "RPPIWebServices" ];

/// *** Deprecated *** Use ServiceName
/// The configuration item name found in HS.Registry.Service.*
Parameter ADAPTER = "EnsLib.SOAP.OutboundAdapter";

Parameter INVOCATION = "Queue";

/// Web services client class
Parameter WEBSERVICECLIENTCLASS As %String = "CUSTOM.BUS.RPPI.Services.SOAP.RPPIServiceClient";

Parameter SETTINGS = "TargetConfigNames:Basic:selector?multiSelect=1&context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},ViewerConfigName:Basic:selector?multiSelect=0&context={Ens.ContextSearch/ProductionItems?targets=1&productionName=@productionId},AdvancedPatientSearchClient:Basic,HealthixSdaWsClient:Basic";

XData MessageMap
{
<MapItems>
	<MapItem MessageType="HS.Message.AddUpdateHubRequest"> 
		<Method>AddUpdateHub</Method>
	</MapItem>
</MapItems>
}

Method AddUpdateHub(pRequest As HS.Message.AddUpdateHubRequest, Output pResponse As CUSTOM.Util.Message.RPPI.AddUpdateHubResponse) As %Library.Status
{
	quit ..invoke("AddUpdateHub",pRequest, .pResponse)
}

/// Invoke a web service request
Method invoke(pMethod As %String, pRequest As Ens.Request, ByRef pResponse As Ens.Response, pMustSend As %Integer = 1) As %Status [ Internal, Private ]
{
	#dim tSC As %Status
	Set tSC=$$$OK,$ZT="Trap"
	Do {
		Set ..Adapter.WebServiceClientClass = ..#WEBSERVICECLIENTCLASS
		//Set the SOAP requestor.
		Set tSC = ..Adapter.%Client.SetHttpHeader("Requestor","EMPL_Edge")
		// Specify the endpoint to connect to
		Set tURL=..HubEndpoint, tEndPoint=""
						
		If ..ServiceName]"" {
			Set tEndPoint = ##class(HS.Registry.Service.SOAP).EndPointForNameType(..ServiceName,"SOAP")
			If $isObject(tEndPoint) {
				Set tURL=tEndPoint.EndPoint
				Set ..Adapter.SOAPCredentials=tEndPoint.UsernameTokenProfileConfig
				$$$TRACE("Set credentials")
				
				Set ..Adapter.SSLConfig=tEndPoint.SSLConfig
			}
		}

		#if $$$HSDebug
			if pMethod'="SyncRequest" { // too many of these
				do ##class(HS.Util.HSDebug).Debug("invoke","HS.Hub.HSWS.RemoteOperations","txt",pMethod_" on "_tURL,pRequest)
			}
		#endif
		
		$$$HSTRACE("URL","tURL,tEndPoint",tURL,tEndPoint)
		Set ..Adapter.WebServiceURL = tURL 
		
		// Set up AdditionalInfo for WSA:From so that it may be
		// passed to the config item that eventually does the
		// ATNA logging for this request.
		Set tHttp = $Select(..Adapter.SSLConfig'="":"https://",1:"http://")
		Set tPort = $Select(^%SYS("WebServer","Port")'="":":"_^%SYS("WebServer","Port"),1:"")
		Set tFrom = tHttp_##class(%SYS.System).GetNodeName(1)_tPort_$system.CSP.GetDefaultApp($namespace)_"/"_..%ClassName(1)_".cls"
		
		// Call the Web Service
		$$$HSPerfStart("Invoke Adapter "_pMethod)
		$$$HSTRACE("Invoking Request"_pMethod,"pRequest",pRequest)
		Set tSC = ..Adapter.InvokeMethod(pMethod, .tResultSC, pRequest, .pResponse)
		$$$HSTRACE("Got Response","tResultSC,tSC,pResponse",tResultSC,tSC,pResponse)
		// Note: If the WebService executes, but fails, you will still get tSC=1 back from the
		//  Adapter, but tResultSC will contain the error message
		$$$HSPerfEnd
		// We retry on connectivity errors, but not application errors
		If $$$ISERR(tSC),pMustSend {
			// Retry if this is a "must send" message.  Actual retry behavior is controlled by the
			// RetryInterval and FailureTimeout operation settings.
			Set ..Retry = 1
		}
		//Handle errors that aren't communication errors
		Set:$$$ISOK(tSC) tSC = tResultSC
			
	} While (0)
Exit
	Quit tSC
Trap
	Set $ZT="",tSC=$S($ZE["ZSOA":%objlasterror,1:$$$EnsSystemError)
	Goto Exit
}

}
