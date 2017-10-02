Class CUSTOM.CORE.Operation.ToRegistryProviderQueryOperation Extends CUSTOM.CORE.Operation.ToRegistryWebServiceClientOperation
{

Parameter INVOCATION = "InProc";

Property ServiceRegistry As %String [ InitialExpression = "CUSTOM.REGISTRY.WS.WebServices" ];

Property ServiceRegistryClient As %String [ InitialExpression = "CUSTOM.REGISTRY.WS.WebServicesClient" ];

Parameter SETTINGS As %String = "ServiceRegistry,ServiceRegistryClient";

XData MessageMap
{
<MapItems>
	<MapItem MessageType="CUSTOM.Util.Message.GetProviderIdentifiersRequest"> 
		<Method>ProviderQuery</Method>
	</MapItem>
</MapItems>
}

Method ProviderQuery(pRequest As CUSTOM.Util.Message.GetProviderIdentifiersRequest, Output pRepsonse As CUSTOM.Util.Message.LoadProviderResponse) As %Status
{

	set tStatus=$$$OK
	Try {
		
		//Step 1 - Get Provider TokenId by passing in Prov LastName and Prov FirstName
		//Set tStatus=..GetToken(pProvLastName,pProvFirstName,.pToken)
		
		//Step 1 - Get Provider ID by passing in AA and SiteID
		Set tStatus=..GetProviderId(pRequest,.tToken)
		
		If ($System.Status.IsError(tStatus)){
			Throw ##Class(%Exception.StatusException).CreateFromStatus(tStatus)
		}

		If tToken="" {
			$$$ThrowStatus($$$ERROR($$$GeneralError,"No provider token returned."))	
		}
		
		//Step 2 - Get provider info
		Set tStatus=..GetProviderInfo(tToken,.pRepsonse)
		
		If ($System.Status.IsError(tStatus)){
			Throw ##Class(%Exception.StatusException).CreateFromStatus(tStatus)
		}	
				
	}
	Catch exception {
		Set tStatus=exception.AsStatus()
		$$$LOGERROR("Error in ToRegistryProviderQueryOperation : "_$System.Status.GetErrorText(tStatus))
	}
	Quit tStatus
}

Method GetToken(pProvLastName As %String, pProvFirstName As %String, Output Token As %String) As %Status
{
	Set Token=""
	set tStatus=$$$OK
	Try {
		
		//Get Provider TokenId by passing in Prov LastName and Prov FirstName
		
		Set FindRequest=##class(CUSTOM.Util.Message.FindProvidersRequest).%New()
		Set FindRequest.LastName=pProvLastName
		Set FindRequest.FirstName=pProvFirstName
		Set MethodName="FindProviders"
		Set status=..callWS(..ServiceRegistry, ..ServiceRegistryClient, MethodName, FindRequest, .FindResponse)
		If ($System.Status.IsError(status)){
			Throw ##Class(%Exception.StatusException).CreateFromStatus(status)
		}
		
		#Dim FindResponse As CUSTOM.Util.Message.FindProvidersResponse
		if FindResponse.Providers.Count() > 0
		{
			#Dim tProvider As CUSTOM.Util.Message.FindProvidersItem
				
			//pull token from first item in response
			set tProvider = FindResponse.Providers.GetAt(1)
			Set:tProvider.Token'="" Token=tProvider.Token
		}
		else
		{
			//no response for provider lookup
			$$$LOGINFO("No Provider ID found for "_pProvLastName_", "_pProvFirstName) 
		}
		
		
	}
	Catch exception {
		Set tStatus=exception.AsStatus()
		$$$LOGERROR("Error in GetToken Method : "_$System.Status.GetErrorText(tStatus))
	}
	Quit Token
}

Method GetProviderId(GetProvIdRequest As CUSTOM.Util.Message.GetProviderIdentifiersRequest, pToken As %String) As %Status
{
	set tStatus=$$$OK
	Try {
		
		Set MethodName="GetSiteIdsFromIdentifier"
		
		Set status=..callWS(..ServiceRegistry, ..ServiceRegistryClient, MethodName, GetProvIdRequest, .GetProvIdResponse)
		If ($System.Status.IsError(status)){
			Throw ##Class(%Exception.StatusException).CreateFromStatus(status)
		}
		
		#Dim GetProvIdResponse As CUSTOM.Util.Message.GetProviderIdentifiersResponse
		
		If GetProvIdResponse.ProviderIdentifiers.Count() > 0
		{
			#Dim tProvider As CUSTOM.Util.Message.GetProviderIdentifiersItem
			Set tProvider=GetProvIdResponse.ProviderIdentifiers.GetAt(i)
			Set pToken = tProvider.ClinicianId_":"_tProvider.Userid
		}
		else
		{
			//no response for provider lookup
			$$$LOGINFO("No Provider Id retrieved for "_GetProvIdRequest.AssigningAuthority_"/"_GetProvIdRequest.SiteId)
		}	
	}
	
	Catch exception {
		Set tStatus=exception.AsStatus()
		$$$LOGERROR("Error in GetProviderId Method : "_$System.Status.GetErrorText(tStatus))
	}
	Quit pToken
}

Method GetProviderInfo(pToken As %String, Output pResponse As CUSTOM.Util.Message.LoadProviderResponse) As %Status
{
	set tStatus=$$$OK
	Try {
		Set LoadRequest=##class(CUSTOM.Util.Message.LoadProviderRequest).%New()
		Set LoadRequest.ProviderToken=pToken
		Set MethodName="LoadProvider"
		Set status=..callWS(..ServiceRegistry, ..ServiceRegistryClient, MethodName, LoadRequest, .LoadResponse)
		If ($System.Status.IsError(status))
		{
			Throw ##Class(%Exception.StatusException).CreateFromStatus(status)
		}
	
		#DIM LoadResponse As CUSTOM.Util.Message.LoadProviderResponse
		If (LoadResponse.LastName'=pProvLastName)!(LoadResponse.FirstName'=pProvFirstName)
		{	
			$$$ThrowStatus($$$ERROR($$$GeneralError,"Possible provider mismatch"))				
		}
	}
	Catch exception {
		Set tStatus=exception.AsStatus()
		$$$LOGERROR("Error in GetProviderInfo Method : "_$System.Status.GetErrorText(tStatus))
	}
	Quit LoadResponse
}

}
