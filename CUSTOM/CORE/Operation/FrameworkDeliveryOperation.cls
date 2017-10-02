Include HS.Common

Class CUSTOM.CORE.Operation.FrameworkDeliveryOperation Extends (Ens.BusinessOperation, Ens.Util.FunctionSet, CUSTOM.CORE.Util.DataDescriptionLookupAndFormator)
{

Parameter SETTINGS = "TargetEmailOperation,TargetArchiveOperation,EmailToList,EmailCCList,EmailFrom,EmailGlobalSubscript";

/// This must be overridden with the value in an Inherited class
Property EmailGlobalSubscript As %String [ InitialExpression = "HIENOTIFICATION" ];

Property TargetEmailOperation As Ens.DataType.ConfigName [ InitialExpression = "CUSTOM.Util.Operation.Email" ];

Property TargetEventAPIOperation As Ens.DataType.ConfigName [ InitialExpression = "CUSTOM.ACCESS01.CareTool.Operations.EventAPI" ];

Property TargetArchiveOperation As Ens.DataType.ConfigName;

Property EmailToList As %String(MAXLEN = 1000);

Property EmailBccList As %String(MAXLEN = 1000);

Property EmailCCList As %String(MAXLEN = 1000);

Property EmailFrom As %String [ InitialExpression = "HIE Notification <NoReply@northwell.edu>" ];

Property WSClientOperation As Ens.DataType.ConfigName [ InitialExpression = "ToRegistryWebServiceClientOperation" ];

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
	Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
	Set pResponse.OKToPurge=1
	
	Try {	
		Set status = ..InitiateDataArray(.DataArray)
		
		//Fetch data for program, subscription and SubscriptionDigits from Cohort table
		Set tSubscriptionDataHelper = ##class(CUSTOM.CORE.Util.SubscriptionDataHelper).%New()
		Set status=tSubscriptionDataHelper.FetchDataFromSubscription(.DataArray, pRequest.Subscription)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		
		//Get subscription info from Cohort table
		Set status=tSubscriptionDataHelper.GetSubscriptionAttributes(.DataArray, pRequest.Subscription)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		Set tCohortEmailSubject = DataArray("EMAILSUBJECTSYNTAX")
		Set tCohortEmailHeader = DataArray("EMAILHEADERSYNTAX")
					
		Set EmailGlobalSubscript=$ZCONVERT(DataArray("COHORT"),"U")_"NOTIFICATION"
		
		//Get message data from HL7
		/*
		Do pRequest.OtherData.Rewind()
		Set hl7Message = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pRequest.OtherData,.status)
		IF (..CheckMessageType(hl7Message,.tCalculatedTriggerEvt,.tMsgSecurity)'=1) {
			Quit
		}
		//Fetch data from HL7 message
		Set DataArray("MSGTYPE")=tCalculatedTriggerEvt
		Set DataArray("MSGSECURITY")=tMsgSecurity
		//Set tHl7DataHelper = ##class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
		//Set status = tHl7DataHelper.GetDataFromHL7(hl7Message,.DataArray)*/
		
		//New approach - ED Discharge
		//Fetch data from HL7 message
		
		Set status = ..PopulateNotificationData(pRequest,.DataArray, .StopProcessing)
		If $System.Status.IsError(status) {
			Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(DataArray("COHORT"),pRequest.Subscription.Subject,pRequest.MPIID,status,"PopulateNotificationData failed.")
		}
		Quit:StopProcessing	
		
		Set status=..SetIndividualFacilityAndHospitalService(.DataArray)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
			
		//Get data from membership	
		Set DataArray("MPIID")=pRequest.MPIID
		//bit 0 is the program based subscription
		Do ..overrideDataArray(.DataArray)
		If ($zboolean(DataArray("SUBSCRIPTIONDIGITS"),(2**0),1)=(2**0)) {
			$$$TRACE("GetDataFromMembership")
			Set status=..GetDataFromMembership(.DataArray)
		}
		ElseIf ($zboolean(DataArray("SUBSCRIPTIONDIGITS"),(2**1),1)=(2**1)) {
			$$$TRACE("GetDataFromMemberExtension")
			Set status=..GetDataFromMemberExtension(.DataArray)
		}
		If $System.Status.IsError(status) {
			Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(DataArray("COHORT"),pRequest.Subscription.Subject,pRequest.MPIID,status,"Failed to get data from membership")
		}
		
		//Get all items (EventType,EncounterType,Facility,Schedule,Practice,Recipient) list in delivery rules
		Set tHelper=##class(CUSTOM.CORE.Util.DeliveryRuleHelper).%New()
		//get comb delivery rule list for this subscription and cohort
		Set tCombDeliveryRuleList=tHelper.GetCombDeliveryRuleList(DataArray("COHORT"),pRequest.Subscription.Subject,.status)
		If $System.Status.IsError(status) {
				Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		
		Set status=$System.Status.OK()
		//go through each comb rule
		For i=1:1:tCombDeliveryRuleList.Count() {
			Try {
				Set status = $$$OK
				Set tCombDeliveryRule=tCombDeliveryRuleList.GetAt(i)
				Set tGroupDigits=tCombDeliveryRule.GetAt("GroupingDigits")
				//Test group digits. 
				//bit 0, insurance
				//bit 1, service
				
				If (..IsDeliveryTrigged(tGroupDigits,.DataArray,pRequest.Subscription)=0) {
					Continue
				}
				Set tDeliveryRuleList=tHelper.GetDeliveryRuleList(tCombDeliveryRule.GetAt("CombDeliveryRuleId"),.status)
				If $System.Status.IsError(status) {
					Throw ##class(%Exception.StatusException).CreateFromStatus(status)
				}
				//go through each rule for this comb rule
				For j=1:1:tDeliveryRuleList.Count() {
					//SD-1563 : Set the subject and header to cohort level.
					Set DataArray("EMAILSUBJECTSYNTAX") = tCohortEmailSubject
					Set DataArray("EMAILHEADERSYNTAX") = tCohortEmailHeader
					Try {
						Set status = $$$OK
						Set tDeliveryRule=tDeliveryRuleList.GetAt(j)
						//get EventType EncounterType Facility Schedule Practice Recipient list for each rule in the combrule
						Set tEventType=tHelper.GetEventTypeList(tDeliveryRule.GetAt("DeliveryRuleId"),.status)
						Set tEncounterType=tHelper.GetEncounterTypeList(tDeliveryRule.GetAt("DeliveryRuleId"),.status)
						Set tFacility=tHelper.GetFacilityList(tDeliveryRule.GetAt("DeliveryRuleId"),.status)
						Set tSchedule=tHelper.GetScheduleList(tDeliveryRule.GetAt("DeliveryRuleId"),.status)
						Set tPractice=tHelper.GetPracticeList(tDeliveryRule.GetAt("DeliveryRuleId"),.status)
						Set tRecipient=tHelper.GetRecipientList(tDeliveryRule.GetAt("DeliveryRuleId"),.status)
						Set DataArray("EMAILSUBJECTSYNTAX")=tHelper.GetSubjectSyntaxBasedOnRule(tDeliveryRule.GetAt("DeliveryRuleId"),DataArray("EMAILSUBJECTSYNTAX"),.status)
						Set DataArray("EMAILHEADERSYNTAX")=tHelper.GetHeaderSyntaxBasedOnRule(tDeliveryRule.GetAt("DeliveryRuleId"),DataArray("EMAILHEADERSYNTAX"),.status)
						If $System.Status.IsError(status) {
							Throw ##class(%Exception.StatusException).CreateFromStatus(status)
						}
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
						
						//$$$LOGINFO("Event: "_tEventTypeString_" Encounter: "_tEncounterTypeString_" Facility: "_tFacilityString_" Recipient: "_tRecipientString)
						If (tEventTypeString'="") && ($FIND(","_tEventTypeString_",",(","_DataArray("MESSAGE")_"_"_DataArray("MSGTYPE")_","))=0) {
							Continue
						}
						If (tEncounterTypeString'="") && ($FIND(","_tEncounterTypeString_",",","_DataArray("ENCTYPE")_",")=0) {
							Continue
						}
						If (tFacilityString'="") && ($FIND(","_tFacilityString_",",","_DataArray("FACILITY")_",")=0) {
							Continue
						}
						
						//Loop each schedule to check the trigger
						If (..IsScheduleTrigged(tSchedule, .DataArray, .status)=0) {
							Continue
						}
						
						//Loop each practice to check the trigger
						If (..IsPracticeTrigged(tPractice, .DataArray, .status)=0) {
							Continue
						}	
											
						If $System.Status.IsError(status) {
							Throw ##class(%Exception.StatusException).CreateFromStatus(status)
						}
						
						//Trigger any Subscripotion Specific checks
						If (..IsSubscriptionSpecificTrigged(.DataArray)=0) {
							Continue
						}
						
						//Loop each recipient to check the type
						//Deliver the Notificaion base on the recipient type
						Set tHtml=""
						Set DataArray("RECIPIENTLIST") = ""
						For x=1:1:tRecipient.Count() {
							Try {
								Set status = $$$OK
								Set tRecipientSetting=tRecipient.GetAt(x)
						
								If (tRecipientSetting.GetAt("Type")="EmailNotification") {	
									If (..IsSendEmail(.DataArray)=1) {
										///Construction email
										If tHtml="" {
											Do ..BuildHtmlEmailBody(.tHtml,.DataArray, .status)
											If $System.Status.IsError(status) {
												Throw ##class(%Exception.StatusException).CreateFromStatus(status)
											}
										}
										Set DataArray("EMAILADDR")=tRecipientSetting.GetAt("Recipient")
										
										// + SD-973
										// special logic that looks for "GetPCPEmailFromSDA" in RecipientList and if found fetches the PCP email address stored in SDA
										If DataArray("EMAILADDR")="GetPCPEmailFromSDA" {
											Set pSDADataHelper=##class(CUSTOM.CORE.Util.SDADataHelper).%New()	
											$$$LOGINFO("Passing in "_DataArray("RISKMRN")_" "_DataArray("RISKASSIGNINGAUTH")_" into GetSDAByMRNWithPatientFilterExtended")										
											set tSC = pSDADataHelper.GetSDAByMRNWithPatientFilterExtended(DataArray("RISKMRN"),DataArray("RISKASSIGNINGAUTH"),"","",1,1)
											$$$ThrowOnError(tSC)
											// overlay DataArray("EMAILADDR") with PCP email address pulled from SDA
											Set DataArray("EMAILADDR")=pSDADataHelper.GetPCPEmailFromSDA()
											$$$LOGINFO("Retrieved email:"_DataArray("EMAILADDR"))
											Set tEnv=$ZConvert(##Class(Workbench.SourceControl.Commander).GetEnvironment(),"u")
											// if stage environment - add "stage_" prefix to email address
											If tEnv="STAGE" {
												If DataArray("EMAILADDR")'="" {
													Set DataArray("EMAILADDR")="stage_"_DataArray("EMAILADDR")
												}
											}
										}
										// - SD-973
										
										If $Get(DataArray("RECIPIENTLIST"))'=""{
											Set DataArray("RECIPIENTLIST")=DataArray("RECIPIENTLIST")_","_DataArray("EMAILADDR")
										}Else{
											Set DataArray("RECIPIENTLIST")=DataArray("EMAILADDR")
										}
										Set status=..SendEmail(tHtml,$$$NULLOREF,.DataArray,.pEmailKey)
										If $System.Status.IsError(status) {
											Throw ##class(%Exception.StatusException).CreateFromStatus(status)
										}
										// +AA SDT-1651 10/13/2015 - Modified to use the Utility class to log the notification data.
										If $Get(DataArray("EMAILKEY"))'=""{
											Set DataArray("EMAILKEY")=DataArray("EMAILKEY")_","_pEmailKey
										}Else{
											Set DataArray("EMAILKEY")=pEmailKey
										}
										// -AA SDT-1651 10/13/2015
									}
								}
								ElseIf (tRecipientSetting.GetAt("Type")="BatchTable")  {
									Set status = ..SaveBatchData(.DataArray, .tRecipientSetting)
									If $System.Status.IsError(status) {
										Throw ##class(%Exception.StatusException).CreateFromStatus(status)
									}
								}
								ElseIf (tRecipientSetting.GetAt("Type")="EnrollProgramMember")  {
									Set status=..EnrollProgramMember(pRequest,.pResponse,tDeliveryRule.GetAt("DeliveryRuleId"),.DataArray)
									If $System.Status.IsError(status) {
										Throw ##class(%Exception.StatusException).CreateFromStatus(status)
									}
								}
								// Async Queue
								ElseIf (tRecipientSetting.GetAt("Type")="PushToAsynQueue") {
									Set status = ..PushToAsyncQueue(.DataArray,pRequest.DocumentId,pRequest.%Id(),tDeliveryRule.GetAt("DeliveryRuleId"))
									If $System.Status.IsError(status) {
										Throw ##class(%Exception.StatusException).CreateFromStatus(status)
									}
												
								}
								ElseIf (tRecipientSetting.GetAt("Type")="EventAPI")  {							
									If ($D(DataArray("RISKMRN")))
									{					
										set pEventApiRequest=##Class(CUSTOM.Util.Message.CareToolEventApiRequest).%New()
										Set pEventApiRequest.memberId=DataArray("RISKMRN")
										set pEventApiRequest.facility = DataArray("FACILITY")
										set pEventApiRequest.admissionDate = DataArray("ADMITTIME")
										set pEventApiRequest.dischargeDate = DataArray("DISCHARGETIME")
										set pEventApiRequest.encounterType = DataArray("ENCTYPE")
										set status=..SendRequestAsync(..TargetEventAPIOperation, pEventApiRequest)
										If $System.Status.IsError(status) {
											Throw ##class(%Exception.StatusException).CreateFromStatus(status)
										}
									}
								}
								Else {
									Do ..SubscriptionSpecificDelivery(.DataArray)
									Do ..SubscriptionSpecificDeliveryWithRequest(.DataArray, pRequest)
								}
							}
							Catch exception {
								Set status=exception.AsStatus()
								Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(DataArray("COHORT"),pRequest.Subscription.Subject,pRequest.MPIID,status)
							}
						}				
						If $Get(DataArray("RECIPIENTLIST"))'=""{
							Set notificationDataRowId=""
							Set status=..AddNotification(.DataArray,pRequest.%Id(),.notificationDataRowId)
						}
						If $System.Status.IsError(status) {
							Throw ##class(%Exception.StatusException).CreateFromStatus(status)
						}
					}
					Catch exception {
						Set status=exception.AsStatus()
						Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(DataArray("COHORT"),pRequest.Subscription.Subject,pRequest.MPIID,status)
					}					
				}			
			}
			Catch exception {
				Set status=exception.AsStatus()
				Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(DataArray("COHORT"),pRequest.Subscription.Subject,pRequest.MPIID,status)
			}
		}	
	} Catch exception {
		Set status=exception.AsStatus()
		if '$D(DataArray("COHORT")) set DataArray("COHORT")="NA"
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(DataArray("COHORT"),pRequest.Subscription.Subject,pRequest.MPIID,status)
	}
	Quit status
}

Method EnrollProgramMember(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse, pDeliveryRule As CUSTOM.CORE.Table.PushNotification.DeliveryRule, ByRef pDataArray As %String) As %Status
{
	Set status=$$$OK
	If (pDataArray("MRN")="") Quit status
	If (pDataArray("MRNASSIGNINGAUTH")="") Quit status	
	Set status =..GetMemberEnrollmentProgram(pDeliveryRule, .pDataArray)	
	Set ToTime = ..GetMemberEnrollmentExpirationDate(pDeliveryRule, .pDataArray)
	If (pDataArray("PROGRAM")="") Quit status
	
	set objMemEnroll=##Class(CUSTOM.CORE.Util.MemberEnrollment).%New()
	set tGenericReq=objMemEnroll.CreateAddUpdateProgramMemberRequest(pDataArray("MRNASSIGNINGAUTH"),pDataArray("MRN"),pDataArray("PROGRAM"),,ToTime)
	set tResponse=##Class(CUSTOM.REGISTRY.ProgramRegistryService.Message.AddUpdateProgramMemberResponse).%New()
	set status=objMemEnroll.AddUpdateProgramMember(tGenericReq, .tResponse)
	If $System.Status.IsError(status) {
		Throw ##class(%Exception.StatusException).CreateFromStatus(status)
	}
	
	//ICIAT - 778
	Set status = ..SearchHoldRepositoryForMessages(pRequest, .pResponse)
	//
	Quit status
}

Method GetMemberEnrollmentProgram(pDeliveryRule As CUSTOM.CORE.Table.PushNotification.DeliveryRule, ByRef pDataArray As %String) As %Status
{
	Set status=$$$OK
	Quit status
}

Method GetMemberEnrollmentExpirationDate(pDeliveryRule As CUSTOM.CORE.Table.PushNotification.DeliveryRule, ByRef pDataArray As %String) As %String
{
	Set tDeliveryRuleHelper=##class(CUSTOM.CORE.Util.DeliveryRuleHelper).%New()
	Set pDataArray("EnrollmentExpirationDays")=tDeliveryRuleHelper.GetMemberEnrollmentExpirationDays(pDeliveryRule)
	
	Set ToTime = "" //Enrollment
	If pDataArray("EnrollmentExpirationDays")=-1 { //Disenrollment, set to Current date
		Set ToTime = $ZDT(+$H_","_$P($H,",",2),3,1)
	}
	elseIf pDataArray("EnrollmentExpirationDays")=0 { //Enrollment with ToTime as blank
		Set ToTime = ""
	}
	elseIf pDataArray("EnrollmentExpirationDays")'="" {
		Set ToTime = $ZDT(+$H+pDataArray("EnrollmentExpirationDays")_","_$P($H,",",2),3,1)
	}
	
	Quit ToTime
}

Method PopulateNotificationData(pRequest As HS.Message.Push.DeliveryRequest, ByRef pDataArray As %String, ByRef pStopProcessing As %String = 0) As %Status
{
		set status = $$$OK
		Do pRequest.OtherData.Rewind()
		Set hl7Message = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pRequest.OtherData,.status)
		IF (..CheckMessageType(hl7Message,.tCalculatedTriggerEvt,.tMsgSecurity)=1) {
			//Fetch data from HL7 message
			Set pDataArray("MSGTYPE")=tCalculatedTriggerEvt
			Set pDataArray("MSGSECURITY")=tMsgSecurity
			Set tHl7DataHelper = ##class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
			Set status = tHl7DataHelper.GetDataFromHL7(hl7Message,.pDataArray)
		}
		Else {
			Set pStopProcessing=1
		}
		quit status
}

Method SearchHoldRepositoryForMessages(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	//ICIAT - 778
	//return OK to do nothing in this base class
	//overwrite this method in extended class to handle checking for Respository hold message for send
	//see CUSTOM.ACCESS01.Article28.Operations.Article28SiuhMcKessonEnroll for example
	quit $$$OK
}

Method InitiateDataArray(pPatDataArray As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	
	/// Others	
	Set pPatDataArray("MPIID") = ""
	Set pPatDataArray("FROMTIME") = ""
	
	Set status = ..InitiateDataArrayExtra(.pPatDataArray)
	
	Quit status
}

Method InitiateDataArrayExtra(pPatDataArray As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Quit status
}

Method IsScheduleTrigged(pSchedule As %ListOfObjects, pPatDataArray As %String, ByRef Status As %Status) As %Boolean
{
	Set Status=$SYSTEM.Status.OK()
	Set IsTrigged=0
	Try {
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
	}
	Catch Exception{
		Set Status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(Status,Exception.AsStatus(),"IsScheduleTrigged Failed.")
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(pPatDataArray("COHORT"),pPatDataArray("SUBSCRIPTIONSUBJECT"),pPatDataArray("MPIID"),Status)
	}
	Quit IsTrigged
}

Method IsDeliveryTrigged(pCheckDigits As %Integer, pPatDataArray As %String, pSubscription As HS.Types.SubscriptionSerialInfo) As %Boolean
{
	Set status=$SYSTEM.Status.OK()
	set IsDeliveryTrigged=1
	Try {
		//Check whether we need to check for Insurance Codes
		/*If ($Zboolean(pCheckDigits,(2**0),1)=(2**0))
		{
			set IsDeliveryTrigged=0
		}*/
		
		//Check whether we need to check for Hospital Service Codes
		If ($Zboolean(pCheckDigits,(2**1),1)=(2**1))
		{
			set IsDeliveryTrigged=0
			//Fetch data for hospital service code
			Set tSubscriptionDataHelper = ##class(CUSTOM.CORE.Util.SubscriptionDataHelper).%New()
			Set tServiceCodes = tSubscriptionDataHelper.GetHospitalServiceCodesBySubscription(.pPatDataArray,pSubscription,.Status)
			If $System.Status.IsError(status) {
				Throw ##class(%Exception.StatusException).CreateFromStatus(status)
			}
			set tServiceCodeList=$LISTFROMSTRING(tServiceCodes,",")
			set serviceCode=pPatDataArray("HOSPITALSVC")
			// Handling serviceCode = "" in Hl7 message; set trigger delivery true by default, if serviceCode is empty,
			If ($$$ISOK(status)){
				For i=1:1:$ListLength(tServiceCodeList){
					Set service=$ListGet(tServiceCodeList,i)
					Set IsExclude = $P(service,"/",2)
					Set service = $P(service,"/",1)
					If (IsExclude=1) {
						Set IsDeliveryTrigged=1
						// Check for empty serviceCode before comparing
						If (serviceCode'="")
						{
							If ((service=serviceCode) || (service=$P(serviceCode,"/",1)) ) {
								Set IsDeliveryTrigged=0 Quit
							}
						}
					}
					// If IsExclude is 0
					Else
						{
							// Check for empty serviceCode before comparing
							If (serviceCode'="")
							{
								If ((service=serviceCode) || (service=$P(serviceCode,"/",1)) ){
								Set IsDeliveryTrigged=1 Quit
								}
							}
						}
					}	
				}
		}
			
	}
	Catch Exception {
		//Set Status=Exception.AsStatus()
		Set Status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(Status,Exception.AsStatus(),"IsDeliveryTrigged failed for CheckDigits: "_pCheckDigits)
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(pPatDataArray("COHORT"),pPatDataArray("SUBSCRIPTIONSUBJECT"),pPatDataArray("MPIID"),Status)
	}
	Quit IsDeliveryTrigged
}

Method IsSubscriptionSpecificTrigged(ByRef pDataArray As %String) As %Boolean
{
	Set Status=$System.Status.OK()
	Try {
	}
	Catch Exception {
		Set Status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(Status,Exception.AsStatus(),"IsSubscriptionSpecificTrigged failed.")
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(pDataArray("COHORT"),pDataArray("SUBSCRIPTIONSUBJECT"),pDataArray("MPIID"),Status)
	}
	Quit 1
}

Method IsPracticeTrigged(pPractice As %ListOfObjects, pPatDataArray As %String, ByRef Status As %Status) As %Boolean
{
	Set Status=$SYSTEM.Status.OK()
	Set IsTrigged=0
	Try {
		Set tObject = ##class(CUSTOM.CORE.Util.DeliveryRuleHelper).%New()		
		Set tHelper = ##class(CUSTOM.CORE.Util.EnframeworkRuleHelper).%New(tObject)
		Set IsTrigged = tHelper.IsPracticeTrigged(pPractice, .pPatDataArray)	
	}
	Catch Exception {
		Set Status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(Status,Exception.AsStatus(),"IsPracticeTrigged failed. Practice Count: "_pPractice.Count())
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(pPatDataArray("COHORT"),pPatDataArray("SUBSCRIPTIONSUBJECT"),pPatDataArray("MPIID"),Status)
	}
	Quit IsTrigged
}

/// This method has to be overridden for adding pre validation before this hl7 message qualify for the notification subscription. 
/// This method does pre validation before this hl7 message qualify for the email notification.
Method CheckMessageType(pMessage As EnsLib.HL7.Message, Output pTriggerEvt As %String = "", Output pMsgSecurity As %String = "") As %Boolean
{
	Set tReturnValue = 1
	Set tHl7DataHelper = ##class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
	Set tRet = tHl7DataHelper.GetMessageType(pMessage, .tMsgType, .tMsgSecurity)	
	If (tRet = 1) {
	 Set pTriggerEvt=tMsgType
	 Set pMsgSecurity=tMsgSecurity
	 // ICIAT-10238 : Modified code to check A06 messages from Soarian.
	 Set tSourceApplication = pMessage.GetValueAt("1:3")
	 If (tMsgType = "A50") {
	 	If (tMsgSecurity = "CHPFXSIA") || (tMsgSecurity = "CHPFADIT") {
			Set pTriggerEvt = "A06"
		} ElseIf (tMsgSecurity = "CHPFXSOA") {
			Set pTriggerEvt = "A07"
		} ElseIf(tSourceApplication = "SFPA+"){
			Set pTriggerEvt = tMsgSecurity
		} Else {
			Set tReturnValue = 0
		}
	 }
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
		set pPatDataArray("PROGRAMFROMTIME")=""
		Set pPatDataArray("PROGRAMMEMBERAA")=""
		//+SDT 2016
		/*Set tProgramMemberHelper = ##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
		Set tProgramMember = tProgramMemberHelper.GetProgramMemberFromMPPID(pPatDataArray("MPIID"), pPatDataArray("PROGRAM"), .status)
		*/
		set objMDH=##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
		set tGenericReq=objMDH.CreateProgramMemberFromMPPIDGenReq(pPatDataArray("MPIID"),pPatDataArray("PROGRAM"))
		set respProgramMember=##Class(CUSTOM.Util.Message.GetProgramMemberV2Response).%New()
		Set status=..SendRequestSync(..WSClientOperation, tGenericReq, .respProgramMember)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		s tProgramMember=$$$NULLOREF
		If respProgramMember.ProgramMembers.Count()>0 {
			Set tProgramMember=respProgramMember.ProgramMembers.GetAt(1)
			if $IsObject(tProgramMember) {
				set:tProgramMember.FromTime'="" pPatDataArray("PROGRAMFROMTIME")=tProgramMember.FromTime_"^"
				_##Class(CUSTOM.CORE.Util.DataDescriptionLookupAndFormator).FormatTimeStamp(tProgramMember.FromTime)
				set:tProgramMember.AssigningAuthority'="" pPatDataArray("PROGRAMMEMBERAA")=tProgramMember.AssigningAuthority
				set:tProgramMember.FromTime'="" pPatDataArray("FROMTIME")=tProgramMember.FromTime	//SDT 2352
			}
		}
		$$$TRACE("Membership: "_pPatDataArray("PROGRAMMEMBERAA")_" : "_pPatDataArray("PROGRAMFROMTIME"))
	}Catch exception{
		Set status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(status,exception.AsStatus(),"GetDataFromMembership failed for Program: "_pPatDataArray("PROGRAM"))
	}
	Quit status
}

Method GetDataFromMemberExtension(ByRef pPatDataArray As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Set pPatDataArray("MemberPracticeAffiliation")=""
		Set pPatDataArray("MemberHighRiskFlag")=""
		Set pPatDataArray("MemberHccScore")=""
		Set pPatDataArray("HealthHome_DirectBillerIndicator")=""
		//Set pPatDataArray("HealthHome_EnrollmentCode")=""
		Set pPatDataArray("HealthHome_MedicaidMemberId")=""
		Set pPatDataArray("HealthHome_ManagedCarePlanMMISId")=""
		Set pPatDataArray("HealthHome_HarpEligibleFlag")=""
		Set pPatDataArray("HARP_Suffix")=""
		
		//ICIAT-6739
        Set pPatDataArray("HealthHome_EnrollmentCode")=""
        Set pPatDataArray("HealthHome_HML")=""
        Set pPatDataArray("HealthHome_DownstreamProvider")=""
        Set pPatDataArray("HealthHome_Hiatus")=""
		

		///For Push based on Patient Program
		Set tProgram=pPatDataArray("PROGRAM")
		If tProgram="" {
			Set status=$SYSTEM.Status.Error("No Patient Program specified")
		}
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		$$$TRACE("RISKMRN: "_pPatDataArray("RISKMRN")_" RISKASSIGNINGAUTH: "_pPatDataArray("RISKASSIGNINGAUTH")_" PROGRAM: "_tProgram)
		//+SDT 2016
		//Set tProgramMemberHelper = ##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
		//Set status = tProgramMemberHelper.GetProgramMemberExtensionByMPIID(.pPatDataArray, tProgram)
		set objMDH=##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
		if ($D(pPatDataArray("RISKMRN"))=0)||($D(pPatDataArray("RISKASSIGNINGAUTH"))=0)
		{
			Set pPatDataArray("RISKMRN")=""
			Set pPatDataArray("RISKASSIGNINGAUTH")=""
			Set tQuery="Select * from CUSTOM_CORE_Table_PushNotification.RiskEdgeAssigningAuthorityPrograms where Program=?"
			Set tRes = ##class(%SQL.Statement).%ExecDirect(,.tQuery,tProgram)
			if (tRes.%Next()){
				if (tRes.Cohort'=""){
					set pPatDataArray("RISKASSIGNINGAUTH")=tRes.Cohort //SD-1708, tRes.AssigningAuthority is CRTL
				}
				else{
					set pPatDataArray("RISKASSIGNINGAUTH")=tRes.AssigningAuthority
				}
			}
			quit:pPatDataArray("RISKASSIGNINGAUTH")=""
			set tGenericReq=objMDH.CreateMRNforAssigningAuthorityGenReq(pPatDataArray("MPIID"),pPatDataArray("RISKASSIGNINGAUTH"))
			set resp=##Class(CUSTOM.Util.Message.GetIdentifiersResponse).%New()
			Set status=..SendRequestSync(..WSClientOperation, tGenericReq, .resp)
			If $System.Status.IsError(status) {
				Throw ##class(%Exception.StatusException).CreateFromStatus(status)
			}
			for cntr=1:1:resp.Identifiers.Count()
			{
				if resp.Identifiers.GetAt(cntr).AssigningAuthority=pPatDataArray("RISKASSIGNINGAUTH")
				{
					set pPatDataArray("RISKMRN")=resp.Identifiers.GetAt(cntr).MRN
					quit
				}
			}
		}
		if (pPatDataArray("RISKMRN")="")||(pPatDataArray("RISKASSIGNINGAUTH")="")
		{
			$$$LOGINFO("No Risk MRN and Risk Assigning Authority is found for MPIID "_pPatDataArray("MPIID")_" And Program "_pPatDataArray("PROGRAM"))
			quit
		}
		set status=objMDH.GetProgramMemberSDAFromMrnAA(pPatDataArray("RISKMRN"),pPatDataArray("RISKASSIGNINGAUTH"),.pPatDataArray,.status)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		//-SDT 2016
		
	}Catch exception{
		Set status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(status,exception.AsStatus(),"GetDataFromMemberExtension failed for Program: "_pPatDataArray("PROGRAM"))
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
		//Set tRes = tStatement.%ExecDirect(,.tQuery,"HealthFirstDailyNotice",pDataArray("SUBSCRIPTIONSUBJECT"),
		Set tRes = tStatement.%ExecDirect(,.tQuery,"HealthFirstDailyNotice",pDataArray("MemberPracticeAffiliation"),
					tEventTime,pDataArray("MSGTYPE"),pDataArray("VISITNUMBER"),pDataArray("MPIID"),pDataArray("MRN"),
					pDataArray("MRNASSIGNINGAUTH"),pDataArray("FACILITY"),pDataArray("LASTNAME")_", "_pDataArray("FIRSTNAME"),pDataArray("DOB"),
					pDataArray("HOSPITALSVC"),pDataArray("ASSIGNEDLOCATIONPOC"),pDataArray("ENCTYPE"),pDataArray("ADMITTINGDOC"),
					pDataArray("DIAGNOSISDESC"),"HealthFirst",$ZDATETIME($HOROLOG),"",0)
					
		If (tRes.%SQLCODE '= 0) {
			$$$LOGWARNING("Insert into table CUSTOM.CORE.Table.PushSubscriptionBatchEntry failed "_tRes.%SQLCODE)
		}		
		
	} Catch exception {
		Set status=exception.AsStatus()
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(pDataArray("COHORT"),pDataArray("SUBSCRIPTIONSUBJECT"),pDataArray("MPIID"),status,"SaveBatchData Failed.")
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

Method IsSendEmail(pDataArray As %String) As %Boolean [ Private ]
{
	Try {
		set bInsFilterCheck=($zboolean(pDataArray("SUBSCRIPTIONDIGITS"),(2**2),1)=(2**2))
		If ((pDataArray("ORIGEVENT")="A50") && (+bInsFilterCheck'=0) && (pDataArray("INSURANCECODEFILTER")'="")) {
			Set i=1
			Set found=0
			Set tInsurancePlanIds = pDataArray("INSURANCES")
			If ##Class(CUSTOM.CORE.Util.DataDescriptionLookupAndFormator).IsMcKesson(pDataArray("FACILITY")) {
				Set tInsurancePlanIds = pDataArray("INSURANCECOMPANIES")
			}
			While((found=0) && ($PIECE(tInsurancePlanIds,",",i)'="")) {
				Set tIns=$PIECE(tInsurancePlanIds,",",i)
				Set j=1
				While((found=0) && ($PIECE(pDataArray("INSURANCECODEFILTER"),",",j)'="")) {
					Set tInsFilter=$PIECE(pDataArray("INSURANCECODEFILTER"),",",j)
					If tIns=tInsFilter Set found=1
					Set j=j+1
				}
				Set i=i+1
			}
			If found=0 {
				Set tReturnValue = 0
				Quit
			}
		}
		
		Set tReturnValue = 1
		//remove duplicate email - This will be handled by Deduplicate Logic
		/*If '(##Class(CUSTOM.CORE.Util.DataDescriptionLookupAndFormator).IsMcKesson(pDataArray("FACILITY"))) && (pDataArray("MSGTYPE")="A04")&&(pDataArray("ENCTYPE")="E")&&((pDataArray("MSGSECURITY")'= "") && (pDataArray("MSGSECURITY")'="CHPFTREG")) {
			Set tReturnValue = 0
		}*/
	}
	Catch exception {
		Set status=exception.AsStatus()
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(pDataArray("COHORT"),pDataArray("SUBSCRIPTIONSUBJECT"),pDataArray("MPIID"),status,"IsSendEmail Failed.")
	}
	Quit tReturnValue
}

/// This method has to be overridden for building the email html content.
/// SDT-2200, Add .status as parameter for standardize error handling, return %Status is kept only for being compatible with existing uses 
Method BuildHtmlEmailBody(pHtml As %String, ByRef pDataArray As %String, ByRef status As %Status = 1) As %Status [ Private ]
{
	//Set status=$SYSTEM.Status.OK()
	Try {
		set objEmailContentUtil=##Class(CUSTOM.CORE.Util.EmailContentUtility).%New()
		Set pDataArray("EMAILHEADER")=objEmailContentUtil.GetEmailHeader(.pDataArray,.status)
		Set pDataArray("EMAILSUBJECT")="PHI: "_objEmailContentUtil.GetEmailSubject(.pDataArray, .status)
		Do objEmailContentUtil.BuildHtmlEmailContent(.pHtml,.pDataArray,.status)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		Do objEmailContentUtil.BuildHtmlEmailContentFooter(.pHtml,.pDataArray, .status)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		
	}Catch exception{
		Set status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(status,exception.AsStatus(),"BuildHtmlEmailBody Failed.")
	}
	Quit status
}

/*Method GetDiagnosisHtmlFromSDA(pSDADataHelper As CUSTOM.CORE.Util.SDADataHelper, pFromTime As %TimeStamp, pVisitNumber = "", pLastVisit As %String) As %String [ Private ]
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
}*/

/*Method GetEncounterHtmlFromSDA(pSDADataHelper As CUSTOM.CORE.Util.SDADataHelper, pFromTime As %TimeStamp, pVisitNumber = "", Output pLastVisit As %String) As %String [ Private ]
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
}*/
Method SendEmail(pHtml As %String, pAttStreams As %Library.ListOfObjects, ByRef pDataArray As %String, ByRef pEmailKey As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	TRY {
		Set tMail=##Class(CUSTOM.Util.Message.EmailRequest).%New()
		Set tMail.Subject=pDataArray("EMAILSUBJECT")
		Set tMail.From=..EmailFrom
		Set tHelper=##Class(CUSTOM.CORE.Util.EmailComposeHelper).%New()
		Set status=..BuildEmailToList(.pDataArray)
		$$$ThrowOnError(status)
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
		//Check for employee health plan and send mail via Access05
		
		Set tCohort = $Get(pDataArray("COHORT"))		
		If tCohort = "EmpHealthPlan"{
			Set tConfig = ##class(HS.Registry.Service.SOAP).EndPointForNameType("CUSTOM.Util.WS.Email.Service.EmailService:ACCESS05","SOAP")
			If (tConfig = "") {
				$$$LOGERROR("Service Registry not configured for Name: CUSTOM.Util.WS.Email.Service.EmailService:ACCESS05")
				$$$ThrowStatus($$$ERROR($$$GeneralError,"Internal Web Service error"))
			}
			Set tClient=##class(CUSTOM.Util.WS.Email.Client.EmailServiceSoap).%New()
			Set tClient.Location=tConfig.EndPoint
			
			If (tConfig.UsernameTokenProfileConfig '= "") {
				Set tCredentials = ##class(Ens.Config.Credentials).%OpenId(tConfig.UsernameTokenProfileConfig)
				Set tSC=tClient.WSSecurityLogin(tCredentials.Username,tCredentials.Password) 
				If $$$ISERR(tSC) $$$ThrowStatus(tSC)
			}
			Set tClient.SSLConfiguration=tConfig.SSLConfig
		
			Set tResponse = ##class(CUSTOM.Util.Message.EmailResponse).%New()	
			Set tResponse = tClient.SendMessage(tMail)
			
		}Else{			
			Set tResponse=##Class(CUSTOM.Util.Message.EmailResponse).%New()
			Set tSC=..SendRequestSync(..TargetEmailOperation, tMail, .tResponse)
		}
		If ($$$ISOK(tSC) && (tResponse.EmailSent = 1)) {
			Set pEmailKey=tResponse.EmailKey
		}
		if (..TargetArchiveOperation '= "") {
			Set tSC = ..SendRequestAsync(..TargetArchiveOperation, tMail)
			$$$ThrowOnError(tSC)
		}
	} Catch exception {
		Set status =  ##class(CUSTOM.CORE.Util.LogUtility).AppendStatus(status,exception.AsStatus(),"SendEmail Failed.")
	}
	Quit status
}

/// This method has to be overridden for building the email-to list.
Method BuildEmailToList(ByRef pDataArray As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Try {
		
	}Catch exception{
		Set status=exception.AsStatus()
	}
	Quit status
}

Method SubscriptionSpecificDelivery(ByRef pDataArray As %String) As %Boolean
{
	Quit 1
}

Method SubscriptionSpecificDeliveryWithRequest(ByRef pDataArray As %String, pRequest As HS.Message.Push.DeliveryRequest) As %Boolean
{
	Quit 1
}

Method overrideDataArray(ByRef pDataArray As %String) As %Status
{
	Quit $$$OK
}

// AA SDT-1651 10/13/2015 - Modified to use the Utility class to log the notification data.

Method AddNotification(ByRef pDataArray As %String, pDeliveryRequestID As %String = "", Output pNotificationDataRowId As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Set pNotificationDataRowId=""
		Set cohort=pDataArray("COHORT")
		Set subscriptionName=pDataArray("SUBSCRIPTIONSUBJECT")
		If ($ZConvert(cohort,"U")["BPCI") {
			Set subscriptionName="BPCINOTIFICATIONS/"_subscriptionName
		}
		Set pDataArray("SUBSCRIPTIONSUBJECT")=subscriptionName
		Set status=##Class(CUSTOM.CORE.Util.NotificationMetricHelper).AddNotificationDataArray(.pDataArray,pDeliveryRequestID,$Get(pDataArray("EMAILKEY")),.pNotificationDataRowId)
	
		/*
		Set tSubject=pDataArray("EMAILSUBJECT")
		Set tMRN=pDataArray("MRN")
		Set tAA=pDataArray("MRNASSIGNINGAUTH")
		Set tFname=pDataArray("FIRSTNAME")
		Set tLname=pDataArray("LASTNAME")
		Set tFromTime=pDataArray("FROMTIME")
		Set tEmailKey=pDataArray("EMAILKEY")
		Set tSubscriptionSubject=pDataArray("SUBSCRIPTIONSUBJECT")
		Set tCohort=pDataArray("COHORT")
		Set status=..AddNotificationData(tCohort,tSubscriptionSubject,tSubject,tMRN,tAA,tFname,tLname,tEmailKey,tFromTime)
		*/
	}
	Catch exception {
		Set status=exception.AsStatus()
		Do ##class(CUSTOM.CORE.Util.LogUtility).LogENFrameworkError(pDataArray("COHORT"),pDataArray("SUBSCRIPTIONSUBJECT"),pDataArray("MPIID"),status,"AddNotification Failed.")
	}
	Quit status
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

Method PushToAsyncQueue(pDataArray As %String, pDocumentId As %String, pObjectId As %String, pDeliveryRule As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Set tQueueRequest = ##class(CUSTOM.Util.Message.FrameworkAsyncQueueRequest).%New()
		Set tQueueRequest.MRN=$Get(pDataArray("MRN"))
		Set tQueueRequest.AssigningAuthority=$Get(pDataArray("MRNASSIGNINGAUTH"))
		Set tQueueRequest.EncounterNumber=$Get(pDataArray("VISITNUMBER"))		
		Set tQueueRequest.MPIID=$Get(pDataArray("MPIID"))
		Set tQueueRequest.EventType = $Get(pDataArray("EVENT"))
		Set tQueueRequest.Cohort = $Get(pDataArray("COHORT"))
		Set tQueueRequest.Subscription=$Get(pDataArray("SUBSCRIPTIONSUBJECT"))
		Set tQueueRequest.DeliveryRule=pDeliveryRule
		Set tQueueRequest.ObjectId=pObjectId
		Set tQueueRequest.DocumentId = pDocumentId
		Set tQueueRequest.InsertTimeStamp = $ZDT($H,3)
		set tQueueRequest.DischargeDateTime = pDataArray("DISCHARGETIME")
		Set tQueueRequest.AsyncDataDigits=0	
	
		//ClinicalBoard
		Set tClinicalMsgRequest = ##class(CUSTOM.Util.Message.ClinicalMsgDeliveryBoardRequest).%New()
		Set tClinicalMsgRequest.APSLINKWEIGHT=$Get(pDataArray("APSLINKWEIGHT"))
		Set tClinicalMsgRequest.FROMTIME=$Get(pDataArray("FROMTIME"))
		Set tClinicalMsgRequest.LACESCORE=$Get(pDataArray("LACESCORE"))
		Set tClinicalMsgRequest.RISKASSIGNINGAUTH=$Get(pDataArray("RISKASSIGNINGAUTH"))
		Set tClinicalMsgRequest.RISKMRN=$Get(pDataArray("RISKMRN"))
		
		Set tQueueRequest.ClinicalMsgDeliveryBoard=tClinicalMsgRequest
		Set status=##class(CUSTOM.CORE.Util.AsyncDeliveryDataHelper).AddToAsyncQueue(tQueueRequest)
	} Catch (Ex) {
		Set status = Ex.AsStatus()
	}
	
	Quit status
}

// Not in use.

/*
Method AddNotificationData(pCohort As %String, pSubscriptionName As %String, pSubject As %String, pMRN As %String, pAA As %String, pFname As %String, pLname As %String, pEmailKey As %String, pFromTime As %TimeStamp) As %Status
{
	
	Set DateEmailSent=+$H
	
	If ($ZCONVERT(pCohort,"U")["BPCI") {
		Set pSubscriptionName = "BPCINOTIFICATIONS/"_pSubscriptionName
	}
	Set status=$SYSTEM.Status.OK()
	Try {
		Set tQuery="INSERT INTO CUSTOM_ACCESS01_Metrics.NotificationData (SubscriptionName,NotificationSubject,DatetimeGenerated,TotalPatientsInNotification,IsReported,Mrn,AssignAuth,Fname,Lname,EmailKey,FromTime) VALUES(?,?,?,?,?,?,?,?,?,?,?)"
		Set tStatement = ##class(%SQL.Statement).%New()
		Set tRes = tStatement.%ExecDirect(,.tQuery,pSubscriptionName,pSubject,DateEmailSent,1,0,pMRN,pAA,pFname,pLname,pEmailKey,pFromTime)		
		If (tRes.%SQLCODE '= 0){
			$$$LOGWARNING("Insert into table CUSTOM_ACCESS01_Metrics.NotificationData failed "_tRes.%SQLCODE)
		}
	}	Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
}
*/
}
