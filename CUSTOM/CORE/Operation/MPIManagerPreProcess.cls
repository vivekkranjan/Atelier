Include HS.Common

Class CUSTOM.CORE.Operation.MPIManagerPreProcess Extends (Ens.BusinessOperation, Ens.Util.FunctionSet, CUSTOM.CORE.Util.DataDescriptionLookupAndFormator)
{

/// Settings for this Business Process
Parameter SETTINGS As %String = "TraceOperations:Dev:selector?Select=1&context={HS.Util.ContextSearch/TraceValues},-FailureTimeout,SearchTimeout,ServiceRegistry";

XData MessageMap
{
<MapItems>
	<MapItem MessageType="HS.Message.IDUpdateNotificationRequest"> 
		<Method>PreProcessIDUpdate</Method>
	</MapItem>
	<MapItem MessageType="HS.Util.EnsRequest"> 
		<Method>ProcessGeneralRequests</Method>
	</MapItem>
</MapItems>
}

/// Process IDUpdateNotificationRequest to check for PriorMPIID
Method PreProcessIDUpdate(pRequest As HS.Message.IDUpdateNotificationRequest, Output pResponse As HS.Message.IDUpdateNotificationRequest) As %Status
{
	//==Init==
	set tSC=$$$OK
	set pResponse=##class(HS.Message.IDUpdateNotificationRequest).%New()

	try {
		//////////////////////////
		set tPriorMPIID = pRequest.PriorMPIID
		set tMPIID = pRequest.MPIID
		
		//Only execute if tPriorMPIID is populated
		if (tPriorMPIID'="")
		{	
			$$$LOGINFO("Detected PriorMPIID")
			Set tSQL = 	"SELECT Ext.ProgramMember as ProgramMember FROM HS_REGISTRY_Program.Member M, "
						_"CUSTOM_REGISTRY_Program.MemberExtension Ext "
						_"where M.ID = Ext.ProgramMember and "
						_"M.MPIID = ?"
		
			set tRS = ##class(%SQL.Statement).%ExecDirect(,.tSQL,tPriorMPIID)
		
			If tRS.%SQLCODE < 0{
				$$$LOGERROR("Error, ProcessIDUpdate, tRS.%SQLCODE:"_tRS.%SQLCODE_", "_tRS.%Message)
            	$$$ThrowStatus($$$ERROR($$$GeneralError, tRS.%SQLCODE_":"_tRS.%Message))
			}
			Else{
				While tRS.%Next()  {
					$$$LOGINFO("Processing results")
					Set tProgramMember=tRS.ProgramMember
					//Add tProgramMember and new MPIID to global
					Set tEntry = tProgramMember_","_tMPIID
					Set $LIST(^zMemberExtensionMergeList,*+1) = tEntry
				}
		  		
			}
		}		
	} 
	catch(e) {
		//Error
		set tSC=e.AsStatus()
		$$$LOGERROR("Error: "_e.AsStatus())
	}
	if $$$ISERR(tSC) {
		$$$LOGERROR($SYSTEM.Status.GetErrorText(tSC))
		
	}
	Set pResponse =pRequest
	Quit $$$OK
}

// Process AddUpdateHubRequest

Method ProcessGeneralRequests(pReq As HS.Util.EnsRequest, Output pResp As HS.Util.EnsRequest) As %Status
{
	   Set pResp = pReq
	   Quit $$$OK
}

}
