Include HS.Common

Class CUSTOM.CORE.Operation.MPIManagerPostProcess Extends (Ens.BusinessOperation, Ens.Util.FunctionSet, CUSTOM.CORE.Util.DataDescriptionLookupAndFormator)
{

/// Settings for this Business Process
Parameter SETTINGS As %String = "TraceOperations:Dev:selector?Select=1&context={HS.Util.ContextSearch/TraceValues},-FailureTimeout,SearchTimeout,ServiceRegistry";

XData MessageMap
{
<MapItems>
	<MapItem MessageType="HS.Message.PostProcessorRequest"> 
		<Method>ProcessIDUpdate</Method>
	</MapItem>
</MapItems>
}

/// Process IdUpdateNotificationRequest to check for PriorMPIID
Method ProcessIDUpdate(pRequest As HS.Message.PostProcessorRequest, Output pResponse As HS.Message.AddUpdateHubResponse) As %Status
{
	//==Init==
	set tSC=$$$OK
	set pResponse=##class(HS.Message.AddUpdateHubResponse).%New()

	try {
		//////////////////////////
		set tRequestString = pRequest.OriginalRequest.XMLExportToString()
		set tPriorMPIID = pRequest.OriginalRequest.PriorMPIID
		set tMPIID = pRequest.OriginalRequest.MPIID
		
		//Only execute if tPriorMPIID is populated
		Set tList=$G(^zMemberExtensionMergeList)
		
   		Set ptr=0
   		Set count=0
   		While $LISTNEXT(tList,ptr,tValue) { 
    		set count=count+1
    		$$$LOGINFO("Value "_count)
    		$$$LOGINFO(tValue)
    		set tProgramMember = $PIECE(tValue,",",1)
    		set tMPIID = $PIECE(tValue,",",2)
   		
		
		if (tPriorMPIID'="")
		{		
			Set tSQL = 	"update CUSTOM_REGISTRY_Program.MemberExtension "
						 	_"set " 
  								_"ProgramMember = mem.ID " 
							_"from "
  							_" CUSTOM_REGISTRY_Program.MemberExtension ext,"
  							_" HS_Registry_Program.Member mem "
							_"where "
  							_"ext.ProgramMember = ? "
  							_"mem.MPIID = ? "		
		
			set tRS = ##class(%SQL.Statement).%ExecDirect(,.tSQL,tProgramMember,tMPIID)
		
			If tRS.%SQLCODE < 0{
				$$$LOGERROR("Error, ProcessIDUpdate, tRS.%SQLCODE:"_tRS.%SQLCODE_", "_tRS.%Message)
            	$$$ThrowStatus($$$ERROR($$$GeneralError, tRS.%SQLCODE_":"_tRS.%Message))
			}
			Else{
				Set ^zzMemberExtensionMergeList = $LISTBUILD()
		  		Set pResponse.ErrStatus   = $$$OK
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
		set pResponse.ErrStatus=$SYSTEM.Status.GetErrorText(tSC)
		
	}
	Quit $$$OK
}

}
