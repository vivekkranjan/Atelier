Include HS.Common

/// 
/// 
/// DO NOT USE - This class is not in use anymore.  We use CUSTOM.CORE.Operation.FrameworkDeliveryOperation in place of this.
/// 
Class CUSTOM.CORE.Operation.PushNotificationFrameworkOperation Extends (Ens.BusinessOperation, Ens.Util.FunctionSet, CUSTOM.CORE.Util.DataDescriptionLookupAndFormator)
{

Parameter SETTINGS = "TargetEmailOperation,TargetArchiveOperation,EmailToList,EmailCCList,EmailFrom,EmailGlobalSubscript,IncludeCareToolLink";

/// This must be overridden with the value in an Inherited class
Property EmailGlobalSubscript As %String [ InitialExpression = "HIENOTIFICATION" ];

Property TargetEmailOperation As Ens.DataType.ConfigName [ InitialExpression = "CUSTOM.Util.Operation.Email" ];

Property TargetArchiveOperation As Ens.DataType.ConfigName;

Property EmailToList As %String(MAXLEN = 1000);

Property EmailBccList As %String(MAXLEN = 1000);

Property EmailCCList As %String(MAXLEN = 1000);

Property EmailFrom As %String [ InitialExpression = "HIE Notification <NoReply@nshs.edu>" ];

/// Include care link if enabled.
Property IncludeCareToolLink As %Boolean [ InitialExpression = 0 ];

XData MessageMap
{
<MapItems>
<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
<Method>DeliverPushNotification</Method>
</MapItem>
</MapItems>
}

Method DeliverPushNotification(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	Set status=$SYSTEM.Status.OK()
	
	Try {		
		Set status = ..InitiateDataArray(.DataArray)
		
		//Fetch data from subscription and SubscriptionDigits from Cohort table
		Set tSubscriptionDataHelper = ##class(CUSTOM.CORE.Util.SubscriptionDataHelper).%New()
		Set status=tSubscriptionDataHelper.FetchDataFromSubscription(.DataArray, pRequest.Subscription)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		
		//Get subscription info from Cohort table
		Set status=tSubscriptionDataHelper.GetSubscriptionDigits(.DataArray, pRequest.Subscription)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		Set EmailGlobalSubscript=$ZCONVERT(DataArray("COHORT"),"U")_"NOTIFICATION"
		
		//Get message data from HL7
		Do pRequest.OtherData.Rewind()
		Set hl7Message = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pRequest.OtherData,.status)
		IF (..CheckMessageType(hl7Message,.tCalculatedTriggerEvt,.tMsgSecurity)'=1) {
			Quit
		}
		//Fetch data from HL7 message
		Set DataArray("MSGTYPE")=tCalculatedTriggerEvt
		Set DataArray("MSGSECURITY")=tMsgSecurity
		Set tHl7DataHelper = ##class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
		Set status = tHl7DataHelper.GetDataFromHL7(hl7Message,.DataArray)
		Set status=..SetIndividualFacilityAndHospitalService(.DataArray)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
			
		//Get data from membership	
		Set DataArray("MPIID")=pRequest.MPIID
		//bit 0 is the program based subscription
		If ($zboolean(DataArray("SUBSCRIPTIONDIGITS"),2**0,1)=1) {
			Set status=..GetDataFromMembership(.DataArray)
		}
		If $System.Status.IsError(status) {
			$$$LOGERROR("Error: CUSTOM.CORE.Operation.BaseEmailOperation failed to get data from membership: "_$SYSTEM.Status.GetErrorText(status))
			//Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		
		//Get all items (EventType,EncounterType,Facility,Schedule,Practice,Recipient) list in delivery rules
		Set tHelper=##class(CUSTOM.CORE.Util.DeliveryRuleHelper).%New()
		//get comb delivery rule list for this subscription and cohort
		Set tCombDeliveryRuleList=tHelper.GetCombDeliveryRuleList(DataArray("COHORT"),DataArray("SUBSCRIPTIONSUBJECT"))
		
		Set status=$System.Status.OK()
			
		//go through each comb rule
		For i=1:1:tCombDeliveryRuleList.Count() {
			Set tCombDeliveryRule=tCombDeliveryRuleList.GetAt(i)
			Set tGroupDigits=tCombDeliveryRule.GetAt("GroupingDigits")
			//Test group digits. 
			//bit 0, insurance
			//bit 1, service
			If (..IsDeliveryTrigged(tGroupDigits)=0) {
				Continue
			}
			
			Set tDeliveryRuleList=tHelper.GetDeliveryRuleList(tCombDeliveryRule.GetAt("CombDeliveryRuleId"))
			//go through each rule for this comb rule
			For j=1:1:tDeliveryRuleList.Count() {
				Set tDeliveryRule=tDeliveryRuleList.GetAt(j)
				//get EventType EncounterType Facility Schedule Practice Recipient list for each rule in the combrule
				Set tEventType=tHelper.GetEventTypeList(tDeliveryRule.GetAt("DeliveryRuleId"))
				Set tEncounterType=tHelper.GetEncounterTypeList(tDeliveryRule.GetAt("DeliveryRuleId"))
				Set tFacility=tHelper.GetFacilityList(tDeliveryRule.GetAt("DeliveryRuleId"))
				Set tSchedule=tHelper.GetScheduleList(tDeliveryRule.GetAt("DeliveryRuleId"))
				Set tPractice=tHelper.GetPracticeList(tDeliveryRule.GetAt("DeliveryRuleId"))
				Set tRecipient=tHelper.GetRecipientList(tDeliveryRule.GetAt("DeliveryRuleId"))
				// create comma separated parameter string
				Set tEncounterTypeString = ""
				Set tEventTypeString = ""
				Set tFacilityString = ""
				Set tScheduleString = ""
				Set tPracticeString = ""
				Set tRecipientString = ""
					
				For x=1:1:tEventType.Count() {
					Set tEventTypeString=tEventTypeString_","_tEventType.GetAt(x).GetAt("EventType")
				}
				If tEventTypeString'="" Set tEventTypeString=$EXTRACT(tEventTypeString,2,*-0)
				For x=1:1:tEncounterType.Count() {
					Set tEncounterTypeString=tEncounterTypeString_","_tEncounterType.GetAt(x).GetAt("EncounterType")
				}
				If tEncounterTypeString'="" Set tEncounterTypeString=$EXTRACT(tEncounterTypeString,2,*-0)
				For x=1:1:tFacility.Count() {
					Set tFacilityString=tFacilityString_","_tFacility.GetAt(x).GetAt("Facility")
				}
				If tFacilityString'="" Set tFacilityString=$EXTRACT(tFacilityString,2,*-0)
				For x=1:1:tSchedule.Count() {
					Set tScheduleString=tScheduleString_","_tSchedule.GetAt(x).GetAt("Schedule")
				}
				If tScheduleString'="" Set tScheduleString=$EXTRACT(tScheduleString,2,*-0)
				For x=1:1:tPractice.Count() {
					Set tPracticeString=tPracticeString_","_tPractice.GetAt(x).GetAt("Practice")
				}
				If tPracticeString'="" Set tPracticeString=$EXTRACT(tPracticeString,2,*-0)
				For x=1:1:tRecipient.Count() {
					Set tRecipientString=tRecipientString_","_tRecipient.GetAt(x).GetAt("Recipient")
				}
				If tRecipientString'="" Set tRecipientString=$EXTRACT(tRecipientString,2,*-0)	
			
				If (tEventTypeString'="") && ($FIND(tEventTypeString,(DataArray("MESSAGE")_"_"_DataArray("MSGTYPE")))=0) {
					Continue
				}
				If (tEncounterTypeString'="") && ($FIND(tEncounterTypeString,DataArray("ENCTYPE"))'=0) {
					Continue
				}
				If (tFacilityString'="") && ($FIND(tFacilityString,DataArray("FACILITY"))=0) {
					Continue
				}
				
				//Loop each schedule to check the trigger
				If (..IsScheduleTrigged(tSchedule)=0) {
					Continue
				}
				
				//Loop each practice to check the trigger
				If (..IsPracticeTrigged(tPractice)=0) {
					Continue
				}
				
				//Loop each recipient to check the type
				//Deliver the Notificaion base on the recipient type
				For x=1:1:tRecipient.Count() {
					Set tRecipientSetting=tRecipient.GetAt(x)
					If (tRecipientSetting.GetAt("Type")="EmailNotification") {
						///Construction email
						Set DataArray("EMAILSUBJECT")=..GetEmailSubject(.DataArray)
						Set status=..BuildHtmlEmailBody(.tHtml,.DataArray)
						If $System.Status.IsError(status) {
							Throw ##class(%Exception.StatusException).CreateFromStatus(status)
						}
						///Send email
						Set DataArray("EMAILADDR")=tRecipientSetting.GetAt("Recipient")
						Set status=..SendEmail(tHtml,$$$NULLOREF,.DataArray,.pEmailKey)
						Set DataArray("EMAILKEY")=pEmailKey
						Set status=..AddNotification(.DataArray)
					}
					ElseIf (tRecipientSetting.GetAt("Type")="BatchTable")  {
						Do ..SaveBatchData(.DataArray, .tRecipientSetting)
					}
				}
				
				If $System.Status.IsError(status) {
					Throw ##class(%Exception.StatusException).CreateFromStatus(status)
				}
			}
		} 	
		Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
		Set pResponse.OKToPurge=1	
	} Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
}

Method InitiateDataArray(pPatDataArray As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	
	/// Others	
	Set pPatDataArray("MPIID") = ""
	Set pPatDataArray("FROMTIME") = ""
	
	//Set status = ..InitiateDataArrayExtra(.pPatDataArray)
	
	Quit status
}

Method IsScheduleTrigged(pSchedule As %ListOfObjects) As %Boolean
{
	Set IsTrigged=0
	Set tCount=pSchedule.Count()
	If tCount=0 Set IsTrigged=1
	For x=1:1:tCount {
		Set tScheduleSetting=pSchedule.GetAt(x)
		Set tCheckWeekdays=tScheduleSetting.GetAt("Weekdays")
		Set tCheckHours=tScheduleSetting.GetAt("Hours")
		Set now=$ZDATETIME($HOROLOG,10,2)
		Set currentHour=$Piece($Piece(now," ",2),":",1)
		Set currentDay=$Piece(now," ",1)
		If currentDay=7 Set currentDay=0
		Set dayBit=2**currentDay
		Set hourBit=2**currentHour
		If ($zboolean(tCheckWeekdays,dayBit,1)'=0&&$zboolean(tCheckHours,hourBit,1)'=0) {
			Set IsTrigged=1
			Quit
		}
	}
	Quit IsTrigged
}

Method IsDeliveryTrigged(pCheckDigits As %Integer) As %Boolean
{
	Quit 1
}

Method IsPracticeTrigged(pPractice As %ListOfObjects) As %Boolean
{
	//query REGISTRY member extended table through web service
	Quit 1
}

/// This method has to be overridden for adding pre validation before this hl7 message qualify for the notification subscription. 
Method CheckMessageType(pMessage As EnsLib.HL7.Message, Output pTriggerEvt As %String = "", Output pMsgSecurity As %String = "") As %Boolean [ Private ]
{
	//Set pTriggerEvt=""
	//Set pMsgSecurity=""
	//Quit 1
	Set tReturnValue = 1
	Set tHl7DataHelper = ##class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
	Set tRet = tHl7DataHelper.GetMessageType(pMessage, .tMsgType, .tMsgSecurity)
	If (tRet = 1) {
	 Set pTriggerEvt=tMsgType
	 Set pMsgSecurity=tMsgSecurity
	}
	ELSE {
		Set tReturnValue = 0
	}
	Quit tReturnValue
}

/// This method get member data based on MRN. The web service GetProgramMembersData is not working if MRN and MRNAssigningAuth are empty in member table
/// Need to fix web service that it will try to get MPIID from patient table   
Method GetDataFromMembership(ByRef pPatDataArray As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		///For Push based on Patient Program
		Set tProgram=pPatDataArray("SUBSCRIPTIONSUBJECT")
		If tProgram="" {
			Set status=$SYSTEM.Status.Error("No Patient Program specified")
		}
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		Set tProgramMemberHelper = ##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
		Set status = tProgramMemberHelper.GetProgramMember(pPatDataArray("MRN"), pPatDataArray("MRNASSIGNINGAUTH"))
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
	}Catch exception{
		Set status=exception.AsStatus()
	}
	Quit status
}

Method SaveBatchData(ByRef pDataArray As %String, pRecipientSetting As %ArrayOfDataTypes) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Set tEventTime=..GetEventTime(.pDataArray)
		
		Set tQuery="insert into CUSTOM_CORE_Table.PushSubscriptionBatchEntry (Notification,Subscription,EventTime,EventDesc,VisitNumber,"
					_"MPIID,MRN,AssigningAuthority,Facility,Patient,DOB,HospitalService,Unit,EncounterType,Doctor,Diagnosis,Cohort,"
					_"InsertTime,ProcessTime,IsProcessed) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"	
		Set tStatement = ##class(%SQL.Statement).%New()
		Set tRes = tStatement.%ExecDirect(,.tQuery,"HealthFirstDailyNotice",pDataArray("SUBSCRIPTIONSUBJECT"),
					tEventTime,pDataArray("MSGTYPE"),pDataArray("VISITNUMBER"),pDataArray("MPIID"),pDataArray("MRN"),
					pDataArray("MRNASSIGNINGAUTH"),pDataArray("FACILITY"),pDataArray("LASTNAME")_", "_pDataArray("FIRSTNAME"),pDataArray("DOB"),
					pDataArray("HOSPITALSVC"),pDataArray("ASSIGNEDLOCATIONPOC"),pDataArray("ENCTYPE"),pDataArray("ADMITTINGDOC"),
					pDataArray("DIAGNOSISDESC"),"HealthFirst",$ZDATETIME($HOROLOG),"",0)
					
		If (tRes.%SQLCODE '= 0) {
			$$$LOGWARNING("Insert into table CUSTOM.CORE.Table.PushSubscriptionBatchEntry failed "_tRes.%SQLCODE)
		}		
		
	} Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
}

Method GetEventTime(ByRef pDataArray As %String, Output pEventTimeName As %String) As %Status [ Private ]
{
	Set tEventTime=""
	Set pEventTimeName="Admit Time:"
	If (pDataArray("MSGTYPE")'="")&&(pDataArray("MSGTYPE")="A03") {
		Set pEventTimeName="Discharge Time:"
		Set tEventTime=pDataArray("DISCHARGETIME")
	}
	ElseIf pDataArray("ADMITTIME")'="" {
		Set tEventTime=pDataArray("ADMITTIME")
	}
	Quit tEventTime
}

Method GetEmailSubject(ByRef pDataArray As %String) As %String [ Private ]
{
	Set emailSubject="Notification of "
					_..Lookup("EventEncounterCombDesc","DEFAULT_"_pDataArray("EVENT")_"_"_pDataArray("ENCTYPE"),"")
					_" at "_pDataArray("FACILITYDESC")
	
	Quit emailSubject
}

Method IsSendEmail(pDataArray As %String) As %Boolean [ Private ]
{
	//remove duplicate email
	Set tReturnValue = 1
	If (pDataArray("MSGTYPE")="A04")&&(pDataArray("ENCTYPE")="E")&&(pDataArray("MSGSECURITY")'="CHPFTREG") {
		Set tReturnValue = 0
	}
	Quit tReturnValue
}

/// This method has to be overridden for building the email html content.
Method BuildHtmlEmailBody(pHtml As %String, ByRef pDataArray As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Set pHtml=""
		 
		/// Construct HTML email body here
		If (..IncludeCareToolLink = 1) {
			Set tEnv = $ZCONVERT(##class(Workbench.SourceControl.Commander).GetEnvironment(),"u")
			If tEnv="DEV"{
				Set pHtml="<A href='http://swbdmstfsap02v/CareTool61_DEV'>DEV Care Tool</A><br>"
			}
			ElseIf tEnv="QA"{
				Set pHtml="<A href='http://swbdmstfsap02v/CareTool61_v1'>QA Care Tool</A><br>"
			}
			ElseIf tEnv="STAGE"{
				Set pHtml="NO STAGE Care Tool<br>"
			}
			ElseIf tEnv="PROD"{
				Set pHtml="<A href='http://caretoolweb/CareTool'>Care Tool</A><br>"
			}
		}
		
		//Set tEventTime=..GetEventTime(.pDataArray, .pEventTimeName)
		Set pHtml=pHtml_"<center><b>"_pDataArray("COHORT")_" Notification of "
					   _..Lookup("EventEncounterCombDesc","DEFAULT_"_pDataArray("EVENT")_"_"_pDataArray("ENCTYPE"),"")
					   _" at "_pDataArray("FACILITYDESC")_"</b></center><br>"
			_"<b>Information Summary:</b><br>"
			_"<table>"
			_"<tr><td>Patient: </td><td>"_pDataArray("LASTNAME")_", "_pDataArray("FIRSTNAME")_"</td></tr>"
		If pDataArray("DOB")'=""{Set pHtml=pHtml_"<tr><td>Date of Birth: </td><td>"_..FormatDate(pDataArray("DOB"))_"</td></tr>"}
		If pDataArray("EPI")'=""{Set pHtml=pHtml_"<tr><td>EPI: </td><td>"_pDataArray("EPI")_"</td></tr>"}
		If pDataArray("MRN")'=""{Set pHtml=pHtml_"<tr><td>MRN: </td><td>"_pDataArray("MRN")_"</td></tr>"}

		If pDataArray("VISITNUMBER")'=""{Set pHtml=pHtml_"<tr><td>Visit Number: </td><td>"_pDataArray("VISITNUMBER")_"</td></tr>"}
		If pDataArray("HOSPITALSVC")'=""{Set pHtml=pHtml_"<tr><td>Hospital Service: </td><td>"_pDataArray("HOSPITALSVC")_"</td></tr>"}
		If (pDataArray("MSGTYPE")="A01") || (pDataArray("MSGTYPE")="A06") {
			If pDataArray("ASSIGNEDLOCATIONPOC")'="" {Set pHtml=pHtml_"<tr><td>Unit: </td><td>"_pDataArray("ASSIGNEDLOCATIONPOC")_"</td></tr>"}
			If pDataArray("ASSIGNEDLOCATIONROOM")'=""{Set pHtml=pHtml_"<tr><td>Room: </td><td>"_pDataArray("ASSIGNEDLOCATIONROOM")_"</td></tr>"}
			If pDataArray("ASSIGNEDLOCATIONBED")'=""{Set pHtml=pHtml_"<tr><td>Bed: </td><td>"_pDataArray("ASSIGNEDLOCATIONBED")_"</td></tr>"}
		}
		If pDataArray("ENCTYPE")'=""{Set pHtml=pHtml_"<tr><td>Encounter type: </td><td>"_$SELECT(pDataArray("ENCTYPE")="E":"Emergency",pDataArray("ENCTYPE")="I":"Inpatient",pDataArray("ENCTYPE")="O":"Outpatient",1:pDataArray("ENCTYPE"))_"</td></tr>"}
		If pDataArray("ADMITTIME")'=""{Set pHtml=pHtml_"<tr><td>Admit Time: </td><td>"_..FormatDateTime(pDataArray("ADMITTIME"))_"</td></tr>"}
		//If tEventTime'=""{Set pHtml=pHtml_"<tr><td>"_pEventTimeName_" </td><td>"_..FormatDateTime(tEventTime)_"</td></tr>"}
		If $TRANSLATE(pDataArray("ADMITTINGDOC"),"^")'=""{Set pHtml=pHtml_"<tr><td>Admitting Doctor: </td><td>"_..FormatDoctor(pDataArray("ADMITTINGDOC"))_"</td></tr>"}
		If pDataArray("DIAGNOSISDESC")'=""{Set pHtml=pHtml_"<tr><td>Admit Diagnosis: </td><td>"_pDataArray("DIAGNOSISDESC")_"</td></tr>"}
		
		Set tSDADataHelper=##class(CUSTOM.CORE.Util.SDADataHelper).%New()
		Do tSDADataHelper.GetSDAByMPIID(pDataArray("MPIID"))
		Set pHtml = pHtml_..GetEncounterHtmlFromSDA(tSDADataHelper,..HL7ToTimestamp(pDataArray("ADMITTIME")),pDataArray("VISITNUMBER"),.tLastVisit)
		IF tLastVisit '=""
		{
			Set pHtml=pHtml_..GetDiagnosisHtmlFromSDA(tSDADataHelper,..HL7ToTimestamp(pDataArray("ADMITTIME")),pDataArray("VISITNUMBER"),tLastVisit)
		}
		
		Set pHtml=pHtml_"</table><br>"
		Set pHtml=pHtml_"<i>Please do not reply to this email.</i>"
		///
	}Catch exception{
		Set status=exception.AsStatus()
	}
	Quit status
}

Method GetDiagnosisHtmlFromSDA(pSDADataHelper As CUSTOM.CORE.Util.SDADataHelper, pFromTime As %TimeStamp, pVisitNumber = "", pLastVisit As %String) As %String [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	set html = ""
	try {
		//Set tSDADataHelper=##class(CUSTOM.CORE.Util.SDADataHelper).%New(pMPIID)
		Set tFinalDiagnosis = pSDADataHelper.GetDiagnosis(pLastVisit)
 		set html = html_tFinalDiagnosis
	} catch ex {
		do $SYSTEM.Status.DisplayError(ex.AsStatus())
	}
	
	if (html = "") {
		set html = "<tr><td>Final Billing Diagnosis:</td><td>No prior final diagnosis</td></tr>"
	}
	else {
		set html = "<tr><td>Final Billing Diagnosis :</td><td>"_tFinalDiagnosis_						"</td></tr>"
	}
	quit html
}

Method GetEncounterHtmlFromSDA(pSDADataHelper As CUSTOM.CORE.Util.SDADataHelper, pFromTime As %TimeStamp, pVisitNumber = "", Output pLastVisit As %String) As %String [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Set pLastVisit=""
	Set html = ""
 	Set thtml="<tr><td><br/><b>Last Admission History</b></td></tr>"
	//Set tSDADataHelper=##class(CUSTOM.CORE.Util.SDADataHelper).%New(pMPIID)
	Set tSortedList = pSDADataHelper.GetEncounters(pVisitNumber)
	For i=1:1:tSortedList.Count(){
		Set enc =  tSortedList.GetAt(i)
		//$$$LOGINFO("EncounterType: "_enc.EncounterType_" Enc. Start: "_$ZDATE(enc.FromTime)_" Enc. End: "_$ZDATE(enc.EndTime)_" pFromTime: "_$ZDATE(pFromTime)_" Now: "_$ZDATE(now))
		set enctype = $CASE(enc.EncounterType,"I":"Inpatient","E":"Emergency",:"Other")
		If ($ZDATETIMEH(enc.FromTime,8) < $ZDATETIMEH(pFromTime,8)){
			Set pLastVisit=enc.EncounterNumber
			Set tFacility = ..GetFacilityDescription(enc.HealthCareFacility.Organization.Code,.status)
			Set html = thtml_"<tr><td> Type:</td><td>"_
				$ZCVT(enctype,"O","HTML")_"</td></tr>"_
				"<tr><td> Facility:</td><td>"_tFacility_"</td></tr>"_
				"<tr><td> Admission Date:</td><td>"_..FormatTimeStamp(enc.FromTime)_"</td></tr>"
			If enc.EncounterType '="E"{	
				If enc.ToTime'=""{
					Set html = html_"<tr><td> Discharge Date:</td><td>"_$S(enc.EndTime'="":..FormatTimeStamp(enc.ToTime), 1:"")_"</td></tr>"
				}
			}
			Quit
		}
	}
	If (html = ""){
		set html = thtml_" <tr><td> Type:</td><td>No prior Inpatient or ED encounters</td></tr>"
	}
	$$$ThrowOnError(status)
	quit html
}

Method SendEmail(pHtml As %String, pAttStreams As %Library.ListOfObjects, ByRef pDataArray As %String, ByRef pEmailKey As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	TRY {
		Set tMail=##Class(CUSTOM.Util.Message.EmailRequest).%New()
		Set tMail.Subject=pDataArray("EMAILSUBJECT")
		Set tMail.From=..EmailFrom
		Set tHelper=##Class(CUSTOM.CORE.Util.EmailComposeHelper).%New()
		Set toList=pDataArray("EMAILADDR")
		Set status=tHelper.ComposeEmailTo(toList,"",..EmailGlobalSubscript,.tMail)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		Set tMail.Message=pHtml
		
		If ($IsObject(pAttStreams)) {
			For i=1:1:pAttStreams.Count() {
				Set tMail.AttachmentStream = pAttStreams.GetAt(i)
				Set tMail.AttachmentFileName = pDataArray("ATTACHMENTNAME",i)
				Set tMail.AttachmentIsBinary = 1 // hardcoded for now
				Quit // Only 1 attachment is supported for now
			}
		}
			
		Set tResponse=##Class(CUSTOM.Util.Message.EmailResponse).%New()
		Set tSC=..SendRequestSync(..TargetEmailOperation, tMail, .tResponse)
		If ($$$ISOK(tSC) && (tResponse.EmailSent = 1)) {
			Set pEmailKey=tResponse.EmailKey
		}
							
		if (..TargetArchiveOperation '= "") {
			Set tSC = ..SendRequestAsync(..TargetArchiveOperation, tMail)
			$$$ThrowOnError(tSC)
		}
	} Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
}

Method AddNotification(ByRef pDataArray As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Set tSubject=pDataArray("EMAILSUBJECT")
	Set tMRN=pDataArray("MRN")
	Set tAA=pDataArray("MRNASSIGNINGAUTH")
	Set tFname=pDataArray("FIRSTNAME")
	Set tLname=pDataArray("LASTNAME")
	Set tFromTime=pDataArray("FROMTIME")
	Set tEmailKey=pDataArray("EMAILKEY")
	Set tSubscriptionSubject=pDataArray("SUBSCRIPTIONSUBJECT")
	Set status=..AddNotificationData(tSubscriptionSubject,tSubject,tMRN,tAA,tFname,tLname,tEmailKey,tFromTime)
	Quit status
}

Method AddNotificationData(pSubscriptionName As %String, pSubject As %String, pMRN As %String, pAA As %String, pFname As %String, pLname As %String, pEmailKey As %String, pFromTime As %TimeStamp) As %Status
{
	Set DateEmailSent=+$H
	&sql(
		INSERT INTO CUSTOM_ACCESS01_Metrics.NotificationData 
		(SubscriptionName,NotificationSubject,DatetimeGenerated,TotalPatientsInNotification,IsReported,Mrn,AssignAuth,Fname,Lname,EmailKey,FromTime)
		VALUES(:pSubscriptionName,:pSubject,:DateEmailSent,1,0,:pMRN,:pAA,:pFname,:pLname,:pEmailKey,:pFromTime)
	)
	If (SQLCODE'=0){
		QUIT $$$ERROR($$$GeneralError,"Failed adding record into NotificationData table. Error code: "_SQLCODE_"/"_%msg)
	}	
	QUIT $$$OK
}

}
