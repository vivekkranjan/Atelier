Class CUSTOM.CORE.Operation.FrameworkApsDeliveryOperation Extends CUSTOM.CORE.Operation.FrameworkDeliveryOperation
{

Property RiskEdgeMRN As %String;

Property RiskEdgeAssigningAuthority As %String;

Property RankOrScore As %String;

Property FromTime As %TimeStamp;

Property Cohort As %String;

Property CohortMRN As %String;

Property RPPIID As %String;

Property TargetAPSOperation As Ens.DataType.ConfigName [ InitialExpression = "ToRegistryAdvPatientSearchWsClient" ];

Property TriggerProgram As %String [ InitialExpression = 0 ];

Property SubscriptionType As %String [ InitialExpression = "Default" ];

Parameter SETTINGS = "TargetAPSOperation:Basic";

XData MessageMap
{
<MapItems>
<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
<Method>DeliverApsPushNotification</Method>
</MapItem>
</MapItems>
}

// +SD-127

Method Prepare(pRequest As HS.Message.Push.DeliveryRequest, ByRef pDataArray As %String) As %Status
{
	set tSC = $$$OK
	Do pRequest.OtherData.Rewind()
	Set tHL7Message = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pRequest.OtherData,.status)
	If (..CheckMessageType(tHL7Message,.tCalculatedTriggerEvt,.tMsgSecurity) = 1) {
		set obj=##Class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
		set tSC=obj.GetMRNAssigningAuthority(tHL7Message,.pDataArray)
	}
	Quit tSC
}

Method GetSubscriptionValue(pRequest As HS.Message.Push.DeliveryRequest, crrPrg As %String, pSubscriptionType As %String) As %String
{
	Set tSubscription = ""  
	Set tQuery="Select Subscription,SubscriptionDigits from CUSTOM_Push_Table.Cohort where Program=? and SubscriptionType=?"    
	Set tRes = ##class(%SQL.Statement).%ExecDirect(,.tQuery,crrPrg,pSubscriptionType)
	While (tRes.%Next()){
		//Dummy Subscription Check
		If ($zboolean(tRes.SubscriptionDigits,(2**4),1)=(2**4)) {
			Continue
		}
		Else {
			set tSubscription=tRes.Subscription
		}
	}
	quit tSubscription
}

// -SD-127

Method DeliverApsPushNotification(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	set tStatus=$$$OK
	Try {
		//Call APS
		//Do pRequest.OtherData.Rewind()
		//Set tHL7Message = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pRequest.OtherData,.status)
		//Quit:'..CheckMessageType(tHL7Message,.tCalculatedTriggerEvt,.tMsgSecurity) 
		//set obj=##Class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
		//set tSC=obj.GetMRNAssigningAuthority(tHL7Message,.tDataArray)
		//SD-127
		Do ..Prepare(pRequest, .tDataArray)
		if '$D(tDataArray("MRN"))
		{
			$$$LOGINFO("FrameworkApsDeliveryOperation : MRN is not present in PID Segment")
			Quit
		}
		
		set tAA=tDataArray("MRNASSIGNINGAUTH")
		set tMRN=tDataArray("MRN")
		set tMPIID=pRequest.MPIID
		set objAPS=##class(CUSTOM.CORE.Util.APSUtility).%New()
		
		set tRequest=objAPS.GetAPSRequestObject(tMRN,tAA,"")
		Set tResponse=##Class(HS.Message.PatientSearchResponse).%New()
		Set tSC=..SendRequestSync(..TargetAPSOperation, tRequest, .tResponse)
		
		set tStatus=objAPS.GetAPSDataArray(tResponse,tAA,.tAssPatArr,..TriggerProgram)
		$$$ThrowOnError(tStatus)
		// Notification per program
		set NotifiyPRG=""
		$$$TRACE("GetAPSDataArray: "_tAssPatArr)
		For tCtrPrg=1:1:$L(tAssPatArr,",")
		{
			set tNode=$Piece(tAssPatArr,",",tCtrPrg)
			set crrPrg=$Piece(tNode,$C(127),1)
			Continue:crrPrg=""
			Continue:$D(NotifiyPRG(crrPrg))	//Dont send notification if already sent for current Program
			set ..RiskEdgeAssigningAuthority=$Piece(tNode,$C(127),2)
			set ..RiskEdgeMRN=$Piece(tNode,$C(127),3)
			set pRequest.MPIID=$Piece(tNode,$C(127),4)
			set ..RankOrScore=$Piece(tNode,$C(127),5)
			set ..Cohort=$Piece(tNode,$C(127),6) //SD-1708
			if ..Cohort="na" set ..Cohort=""
			
			//SD-127
			set tSubscription = ..GetSubscriptionValue(pRequest,crrPrg,..SubscriptionType)
			Continue:tSubscription=""

			//$$$LOGINFO("Subscription: "_tSubscription_" crrPrg: "_crrPrg)
			set pRequest.Subscription.Subject=tSubscription
			
			//+SDT2016
			// Now check the MPIID is active member for the current Program
			set objMDH=##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
			set tGenericReq=objMDH.CreateProgramMemberFromMPPIDGenReq(pRequest.MPIID,crrPrg)
			set respProgramMember=##Class(CUSTOM.Util.Message.GetProgramMemberV2Response).%New()
			Set status=..SendRequestSync(..WSClientOperation, tGenericReq, .respProgramMember)
			If $System.Status.IsError(status) {
				Throw ##class(%Exception.StatusException).CreateFromStatus(status)
			}
			Set tProgramMember=$$$NULLOREF
			If respProgramMember.ProgramMembers.Count()>0 {
				Set tProgramMember=respProgramMember.ProgramMembers.GetAt(1)
			}
			//-SDT 2016
			if '$IsObject(tProgramMember)
			{
				$$$LOGINFO("FrameworkApsDeliveryOperation : "_pRequest.MPIID_" may not be a member or not an active member of "_crrPrg)
				Continue
			}
			if 'tProgramMember.Active
			{
				$$$LOGINFO("FrameworkApsDeliveryOperation : "_pRequest.MPIID_" is not an active member of "_crrPrg)
				Continue
			}
			set NotifiyPRG(crrPrg)=""
			set ..FromTime=tProgramMember.FromTime	//SDT 2352
			set ..RiskEdgeMRN=tProgramMember.MRN	//SD-922 Get Active Risk MRN
			set ..RiskEdgeAssigningAuthority=tProgramMember.AssigningAuthority
			
			//SD-1708 
			//Implement 4.2 in the design doc
			//If RiskEdgeAssigningAuthority is CRTL (not include BPCI), we need get the Cohort AA and MRN
			if (..Cohort'=""){
				set ..RiskEdgeAssigningAuthority=..Cohort
				set ..RPPIID=..RiskEdgeMRN
				set ..RiskEdgeMRN=..GetCohortMRNFromAPSResponse(tResponse, ..Cohort, pRequest.MPIID)
				set ..CohortMRN=..RiskEdgeMRN
			}
			$$$TRACE("RiskEdgeAssigningAuthority: "_..RiskEdgeAssigningAuthority_" RiskEdgeMRN: "_..RiskEdgeMRN)
			set status=..DeliverPushNotification(pRequest,.pResponse)
			If ($System.Status.IsError(status))
			{
				$$$LOGERROR("Error in FrameworkApsDeliveryOperation : "_$System.Status.GetErrorText(status))
			}
		}
		Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
		Set pResponse.OKToPurge=1
	}
	Catch exception {
		Set tStatus=exception.AsStatus()
		$$$LOGERROR("Error in FrameworkApsDeliveryOperation : "_$System.Status.GetErrorText(tStatus))
	}
	quit tStatus
}

Method GetCohortMRNFromAPSResponse(pAPSResponse As HS.Message.PatientSearchResponse, pCohort As %String, pMPIID As %String) As %String
{
	set tMRN=""
	if pAPSResponse.ResultsCount>0{
		for i=1:1:pAPSResponse.Results.Count(){
			set tResultObj=pAPSResponse.Results.GetAt(i)
			if (tResultObj.AssigningAuthority=pCohort) && (tResultObj.MPIID=pMPIID){
				set tMRN=tResultObj.MRN
				quit
			}
		}
	}
	quit tMRN
}

Method overrideDataArray(ByRef pDataArray As %String) As %Status
{
	set pDataArray("APSLINKWEIGHT")=..RankOrScore
	//+SDT 2016
	set pDataArray("RISKMRN")=..RiskEdgeMRN
	set pDataArray("RISKASSIGNINGAUTH")=..RiskEdgeAssigningAuthority
	//-SDT 2016
	set pDataArray("FROMTIME")=..FromTime	//SDT 2352
	
	set pDataArray("RPPIID")=..RPPIID
	set pDataArray("COHORTMRN")=..CohortMRN
	Quit $$$OK
}

/*Method eValRangeCondition(pRange As %String) As %Boolean
{
	set bRetVal=0
	if pRange["-" //44 -55
	{
		set bRetVal=(..RankOrScore >= +$P(pRange,"-",1))&& (..RankOrScore < +$P(pRange,"-",2))
	}
	elseif pRange[">"  // > 55
	{
		set bRetVal=(..RankOrScore > +$P(pRange,">",2))
	}
	elseif pRange["<" // <55
	{
		set bRetVal=(..RankOrScore < +$P(pRange,"<",2))
	}
	elseif pRange["=" // =44
	{
		set bRetVal=(..RankOrScore = +$P(pRange,"=",2))
	}
	quit bRetVal
}*/
Method IsSubscriptionSpecificTrigged(ByRef pDataArray As %String) As %Boolean
{
	Set tStatus=0
	
	Try {
		set objEmailContentUtil=##Class(CUSTOM.CORE.Util.EmailContentUtility).%New()
		Set tStatus = objEmailContentUtil.CreateAPSEmailContent(.pDataArray)
		}Catch exception{
		Set tSc=exception.AsStatus()
		set tStatus=0
	}	
	Quit tStatus
	
	/*set tThreshHold=""
	Try{
		Set tQuery="SELECT * FROM CUSTOM_CORE_Table.AdvancedPatientSearchLinkThresholdBreakDown WHERE Subscription=?"
		Set tRes = ##class(%SQL.Statement).%ExecDirect(,.tQuery,pDataArray("SUBSCRIPTIONSUBJECT"))
		set tGotResult=0
		while (tRes.%Next()){
			set tGotResult=1
			set tThreshHold=tRes.Threshold
			if (..eValRangeCondition(tThreshHold))
			{
				if tRes.ActionType="EmailContent"
				{
					set tKey="NOTIFICATION_"_pDataArray("EVENT")_"_"_pDataArray("ENCTYPE")
					set eventExcounterCombDesc=##Class(CUSTOM.CORE.Util.DataDescriptionLookupAndFormator).Lookup("EventEncounterCombDesc",tKey)
					set customText=pDataArray("COHORT")_" Cohort has "_
				 	eventExcounterCombDesc_" At "_pDataArray("FACILITYDESC")
				 	
				 	set staticText=". Please verify member eligibility."
				 	
				 	Set pDataArray("EMAILSUBHEADER")=$Case(tRes.Action,
				 	"Moderate":"High probability that patient belonging to "_customText_staticText,
				 	"Low":"Patient may be belonging to "_customText_staticText,
				 	"High":"Patient belonging to "_customText_".")
				 	
				 	set tStatus=1
				}
				elseif tRes.ActionType="EmailSubject"
				{
					set query="Select * from CUSTOM_CORE_Table_PushNotification_EmailContent.SubjectTemplate where ID=?"
					Set tResult = ##class(%SQL.Statement).%ExecDirect(,.query,tRes.Action)
					if (tResult.%Next())
					{
						 Set pDataArray("EMAILSUBJECTSYNTAX")=tResult.Subject
						 set tStatus=1
					}
				}
				elseif tRes.ActionType="EventLog"
				{
					$$$LOGINFO(tRes.Action)
				}
				$$$LOGINFO("FrameworkApsDeliveryOperation : Threshold Range matched : "_tThreshHold_" : "_..RankOrScore)
			}
			else
			{
				$$$LOGINFO("FrameworkApsDeliveryOperation : Threshold Range does not match : "_tThreshHold_" : "_..RankOrScore)
			}
			
		}
		if 'tGotResult=0
		{
			$$$LOGINFO("FrameworkApsDeliveryOperation : CUSTOM_CORE_Table.AdvancedPatientSearchLinkThresholdBreakDown is not setup against subscription "_pDataArray("SUBSCRIPTIONSUBJECT"))
		}
		
	}Catch exception{
		Set tSc=exception.AsStatus()
		set tStatus=0
	}
	
	Quit tStatus*/
}

}
