Include Ensemble

Class CUSTOM.CORE.Operation.ToRegistryWebServiceClientOperation Extends Ens.BusinessOperation
{

Parameter INVOCATION = "InProc";

Property ServiceRegistry As %String [ InitialExpression = "CUSTOM.REGISTRY.WS.WebServices" ];

Property ServiceRegistryClient As %String [ InitialExpression = "CUSTOM.REGISTRY.WS.WebServicesClient" ];

Parameter SETTINGS As %String = "ServiceRegistry,ServiceRegistryClient";

XData MessageMap
{
<MapItems>
	<MapItem MessageType="CUSTOM.Util.Message.GenericRequest"> 
		<Method>GenericCallWS</Method>
	</MapItem>
</MapItems>
}

Method GenericCallWS(pRequest As CUSTOM.Util.Message.GenericRequest, Output pResponse As Ens.Response) As %Status
{
	//$$$LogInfo("In GenericCallWS")  
	set tStatus=$$$OK
	Try {
		//Custom Override (May be used if CUSTOM.REGISTRY.WS.WebServices is broken into multiple services)
		set:pRequest.ServiceRegistry'="" ..ServiceRegistry=pRequest.ServiceRegistry
		set:pRequest.ServiceRegistryClient'="" ..ServiceRegistryClient=pRequest.ServiceRegistryClient
		//
		Set status=..callWS(..ServiceRegistry, ..ServiceRegistryClient, pRequest.MethodName, pRequest.Request, .pResponse)
		If ($System.Status.IsError(status)){
			Throw ##Class(%Exception.StatusException).CreateFromStatus(status)
		}
	}
	Catch exception {
		//$$$LogInfo("In Catch GenericCallWS") 
		Set tStatus=exception.AsStatus()
		$$$LOGERROR("Error in ToRegistryWebServiceClientOperation : "_$System.Status.GetErrorText(tStatus))
	}
	Quit tStatus
}

Method callWS(pServiceRegistry As %String, pClientClass As %String, pMethod As %String, pRequest As Ens.Request, Output pResponse As Ens.Response) As %Status [ Private ]
{
	#Dim tClient As %SOAP.WebClient
	Set tSC = $$$OK, tClient = $$$NULLOREF, pResponse = $$$NULLOREF
	
	try {
		Set tConfig = ##class(HS.Registry.Service.SOAP).EndPointForNameType(pServiceRegistry,"SOAP")
		if (tConfig = "") {
			$$$LOGERROR("Service Registry not configured for Name: "_pServiceRegistry)
			$$$ThrowStatus($$$ERROR($$$GeneralError,"Internal Web Service error"))
		}

		Set tClient=$CLASSMETHOD(pClientClass, "%New")
		Set tClient.Location=tConfig.EndPoint
		if (tConfig.UsernameTokenProfileConfig '= "") {
			Set tCredentials = ##class(Ens.Config.Credentials).%OpenId(tConfig.UsernameTokenProfileConfig)
			Set tSC=tClient.WSSecurityLogin(tCredentials.Username,tCredentials.Password) 
			If $$$ISERR(tSC) $$$ThrowStatus(tSC)
		}
		Set tClient.SSLConfiguration=tConfig.SSLConfig

		Set pResponse = $METHOD(tClient, pMethod, pRequest)
	} catch (ex) {
		if ($IsObject(tClient) && (tClient.SoapFault '= "")) {
			Set tSC = $$$ERROR($$$GeneralError, tClient.SoapFault.faultstring)
		} else {
			set tSC = ex.AsStatus()
		}
	}
	
	Quit tSC
}

}
