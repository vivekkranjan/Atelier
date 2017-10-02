Include (HS.Common, %callout, %ZHSLIB)

/// Base class for eMail Operation which will be used for notification
Class CUSTOM.CORE.Operation.BaseEmailOperation Extends (Ens.BusinessOperation, Ens.Util.FunctionSet, CUSTOM.CORE.Util.DataDescriptionLookupAndFormator)
{

Parameter SETTINGS ="TargetEmailOperation,TargetArchiveOperation,EmailToList,EmailCCList,EmailFrom,ServiceRegistry,IsProgramDataEnabled";

/// This must be overridden with the value in an Inherited class added comment
Property EmailGlobalSubscript As %String;

Property TargetEmailOperation As Ens.DataType.ConfigName [ InitialExpression = "CUSTOM.Util.Operation.Email" ];

Property TargetArchiveOperation As Ens.DataType.ConfigName;

Property EmailToList As %String(MAXLEN = 1000);

Property EmailBccList As %String(MAXLEN = 1000);

Property EmailCCList As %String(MAXLEN = 1000);

Property EmailFrom As %String [ InitialExpression = "HIE Notification <NoReply@northwell.edu>" ];

Property IsProgramDataEnabled As %Boolean [ InitialExpression = 0 ];

XData MessageMap
{
<MapItems>
<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
<Method>SendNotification</Method>
</MapItem>
</MapItems>
}

Method SendNotification(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {		
			Set status=..SendNotificationBasedOnHL7(pRequest,.DataArray)
			If $System.Status.IsError(status) {
				Throw ##class(%Exception.StatusException).CreateFromStatus(status)
			}
			
			Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
			Set pResponse.OKToPurge=1
	} Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
}

Method SendNotificationBasedOnHL7(pRequest As HS.Message.Push.DeliveryRequest, ByRef DataArray As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Do pRequest.OtherData.Rewind()
		Set hl7Message = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pRequest.OtherData,.status)

		IF (..CheckMessageType(hl7Message,.tCalculatedTriggerEvt,.tMsgSecurity)=1) {
			///Fetch data from HL7 message
			Set status = ..InitiateDataArray(.DataArray)
			Set DataArray("MSGTYPE")=tCalculatedTriggerEvt
			Set DataArray("MSGSECURITY")=tMsgSecurity
			Set tHl7DataHelper = ##class(CUSTOM.CORE.Util.Hl7DataHelper).%New()
			Set status = tHl7DataHelper.GetDataFromHL7(hl7Message,.DataArray)
			Set status=..SetFacilityAndHospitalService(.DataArray)
			If $System.Status.IsError(status) {
				Throw ##class(%Exception.StatusException).CreateFromStatus(status)
			}
			
			///Fetch data from subscription
			Set tSubscriptionDataHelper = ##class(CUSTOM.CORE.Util.SubscriptionDataHelper).%New()
			Set status=tSubscriptionDataHelper.FetchDataFromSubscription(.DataArray, pRequest.Subscription)
			Set DataArray("SUBSCRIPTIONDESC")=..GetRecipientDescBySubscription(DataArray("SUBSCRIPTIONSUBJECT"))
			If $System.Status.IsError(status) {
				Throw ##class(%Exception.StatusException).CreateFromStatus(status)
			}
			
			Set DataArray("MPIID")=pRequest.MPIID
			If (..IsProgramDataEnabled) {
				Set status=..GetDataFromMembership(.DataArray)
			}
			If $System.Status.IsError(status) {
				$$$LOGERROR("Error: CUSTOM.CORE.Operation.BaseEmailOperation failed to get data from membership: "_$SYSTEM.Status.GetErrorText(status))
				//Throw ##class(%Exception.StatusException).CreateFromStatus(status)
			}
			/*
			///For Push based on Patient Program
			If (..IsProgramDataEnabled) {
				Set tProgramMemberHelper = ##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
				Set programMember = tProgramMemberHelper.GetProgramMember(DataArray("MRN"),DataArray("MRNASSIGNINGAUTH"),DataArray("SUBSCRIPTIONSUBJECT"))
				If programMember'="" Set DataArray("FROMTIME")=programMember.FromTime
			}
			Else{
				Set DataArray("FROMTIME")=..HL7ToTimestamp(DataArray("ADMITTIME"))
				//Three years back from now
				//Set rightNow=$HOROLOG
				//Set DataArray("FROMTIME")=$ZDATE($PIECE(rightNow,",",1)-(365*3),3)_" "_$ZTIME($PIECE(rightNow,",",2),1)
			}	
			*/
			If (..IsSendEmail(.DataArray)=1) {		
				///Construction email
				Set DataArray("EMAILSUBJECT")=..GetEmailSubject(.DataArray)
				Set status=..BuildHtmlEmailBody(.tHtml,.DataArray)
				If $System.Status.IsError(status) {
					Throw ##class(%Exception.StatusException).CreateFromStatus(status)
				}
				///Send email	
				Set status=..SendEmail(tHtml,$$$NULLOREF,.DataArray,.pEmailKey)
				Set DataArray("EMAILKEY")=pEmailKey
				
				Set status=##Class(CUSTOM.CORE.Util.NotificationMetricHelper).AddNotificationDataArray(.DataArray,pRequest.%Id(),pEmailKey,.pNotificationDataRowId) ; AA SDT-1651 10/13/2015 - Updated to use Util class to log Notification Data
			}
		}
	} Catch exception {
		Set status=exception.AsStatus()
	}
	Quit status
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

Method GetIsProgramDataEnabled() As %Boolean [ Private ]
{
	Quit 0
}

Method IsSendEmail(pPatDataArray As %String) As %Boolean [ Private ]
{
	Quit 1
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
	Quit $SYSTEM.Status.OK()
}

Method GetEmailSubjectOld(ByRef pDataArray As %String) As %String [ Private ]
{
	Set emailSubject="Notification of "_..Lookup("EncounterTypeDesc",pDataArray("ENCTYPE"),"")_" at "_pDataArray("FACILITYDESC")
	Quit emailSubject
}

Method GetEmailSubject(ByRef pDataArray As %String) As %String [ Private ]
{
	If (pDataArray("EVENT")="A06") || (pDataArray("EVENT")="A07") {
		Set emailSubject="Notification of "_..EventLookup(pDataArray("EVENT"))_" at "_pDataArray("FACILITYDESC")
		Quit emailSubject
	}
	Else {
		Set emailSubject="Notification of "_..Lookup("EncounterTypeDesc",pDataArray("ENCTYPE"),"")_" at "_pDataArray("FACILITYDESC")
		Quit emailSubject
	}
}

Method GetEmailSubjectDefault(ByRef pDataArray As %String) As %String [ Private ]
{
	Set emailSubject="Notification of "
					_..Lookup("EventEncounterCombDesc","DEFAULT_"_pDataArray("EVENT")_"_"_pDataArray("ENCTYPE"),"")
					_" at "_pDataArray("FACILITYDESC")
	
	Quit emailSubject
}

/// This method has to be overridden for building the email html content.
Method BuildHtmlEmailBody(pHtml As %String, ByRef pPatDataArray As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	TRY{
		Set pHtml=""
		///
		/// Construct HTML email body here
		///
	}Catch exception{
		Set status=exception.AsStatus()
	}
	Quit status
}

/// todo: breakdown more 
Method SendEmail(pHtml As %String, pAttStreams As %Library.ListOfObjects, ByRef pDataArray As %String, ByRef pEmailKey As %String) As %Status [ Private ]
{
	Set status=$SYSTEM.Status.OK()
	Set pRecipientList=""
	TRY {
			Set tMail=##Class(CUSTOM.Util.Message.EmailRequest).%New()
			Set tEnv=$ZConvert(##Class(Workbench.SourceControl.Commander).GetEnvironment(),"u")
			Set mailToList=..getEmailToList(.pDataArray)
			Set tMailToList=..EmailToList_","_mailToList
			For i=1:1:$Length(tMailToList,",") {
				Set tTo=$Piece(tMailToList,",",i)
				CONTINUE:tTo=""
				Do tMail.To.Insert(tTo)
			}
			For i=1:1:$LENGTH(..EmailBccList,","){
				Set tBcc = $PIECE(..EmailBccList,",",i)
				CONTINUE:tBcc=""
				Do tMail.Bcc.Insert(tBcc)
			}
			///Do tMail.Bcc.Insert("crusch@nshs.edu") ;Chris wants to be copied always.

			If '(tEnv="PROD"){
				If ($Data(^QAEmailAddress(..EmailGlobalSubscript),tData)=1){
					Set tCntr=1
					WHILE(tCntr>0){
						If $Piece(tData,",",tCntr)'=""{
							Do tMail.To.Insert($Piece(tData,",",tCntr))
							Set tCntr=tCntr+1
						}
						Else{
							Set tCntr=0
						}
					}
				}
			}
			Set tMail.Subject=pDataArray("EMAILSUBJECT")
			Set tMail.From=..EmailFrom
			Set tMail.Message=pHtml
			If ($IsObject(pAttStreams)) {
				For i=1:1:pAttStreams.Count() {
					Set tMail.AttachmentStream = pAttStreams.GetAt(i)
					Set tMail.AttachmentFileName = pDataArray("ATTACHMENTNAME",i)
					Set tMail.AttachmentIsBinary = 1 // hardcoded for now
					Quit // Only 1 attachment is supported for now
				}
			}
			For i=1:1:tMail.To.Count(){
				Set pRecipientList=pRecipientList_tMail.To.GetAt(i)_","
			}
			Set pRecipientList=$Extract(pRecipientList,1,$Length(pRecipientList)-1)
			Set pDataArray("RECIPIENTLIST")=pRecipientList
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

Method GetDataFromMembership(ByRef pPatDataArray As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Do ..GetDataFromMember(.pPatDataArray)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
	}Catch exception{
		Set status=exception.AsStatus()
	}
	Quit status
}

/// This method get member data based on MRN. The web service GetProgramMembersData is not working if MRN and MRNAssigningAuth are empty in member table
/// Need to fix web service that it will try to get MPIID from patient table   
Method GetDataFromMember(ByRef pPatDataArray As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		///For Push based on Patient Program
		Set tProgram=..GetProgram(.pPatDataArray)
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

Method GetDataFromMemberExtension(ByRef pPatDataArray As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		///For Push based on Patient Program
		Set tProgram=..GetProgram(.pPatDataArray)
		If tProgram="" {
			Set status=$SYSTEM.Status.Error("No Patient Program specified")
		}
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
		Set tProgramMemberHelper = ##class(CUSTOM.CORE.Util.MembershipDataHelper).%New()
		Set status = tProgramMemberHelper.GetProgramMemberExtensionByMPIID(.pPatDataArray, tProgram)
		If $System.Status.IsError(status) {
			Throw ##class(%Exception.StatusException).CreateFromStatus(status)
		}
	}Catch exception{
		Set status=exception.AsStatus()
	}
	Quit status
}

Method GetProgram(ByRef pPatDataArray As %String) As %String
{
	Set tProgram=""
	//You can setup subscription subject same as program name so you don't need hard-code the program name. 
	//You can use this relation to identify the program if the email operation is not for one program
	If pPatDataArray("SUBSCRIPTIONSUBJECT") '= "" Set tProgram=pPatDataArray("SUBSCRIPTIONSUBJECT")
	Quit tProgram
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
		$$$LOGINFO("EncounterType: "_enc.EncounterType_" Enc. Start: "_enc.FromTime_" Enc. End: "_enc.EndTime_" pFromTime: "_pFromTime)
		set enctype = $CASE(enc.EncounterType,"I":"Inpatient","E":"Emergency",:"Other")
		If (##class(%Library.UTC).Compare(enc.FromTime, pFromTime)<0){
			Set pLastVisit=enc.EncounterNumber
			Set tFacility = ..GetFacilityDescription(enc.HealthCareFacility.Organization.Code,.status)
			Set html = thtml_"<tr><td> Type:</td><td>"_
				$ZCVT(enctype,"O","HTML")_"</td></tr>"_
				"<tr><td> Facility:</td><td>"_tFacility_"</td></tr>"_
				"<tr><td> Admission Date:</td><td>"_..FormatTimeStamp(enc.FromTime)_"</td></tr>"
			If enc.EncounterType '="E"{	
				If enc.ToTime'=""{
					// ICIAT-6851 - changed enc.EndTime to enc.ToTime to make sure Discharge Date displays in Discharge Summary
					Set html = html_"<tr><td> Discharge Date:</td><td>"_..FormatTimeStamp(enc.ToTime)_"</td></tr>"
					If enc.EndTime="" {
						$$$LOGINFO("CUSTOM.CORE.Operation.BaseEmailOperation - corrected Discharge Date:"_..FormatTimeStamp(enc.ToTime))
					}
					//Set html = html_"<tr><td> Discharge Date:</td><td>"_$S(enc.EndTime'="":..FormatTimeStamp(enc.ToTime), 1:"")_"</td></tr>"
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

Method getEmailToList(ByRef pDataArray As %String) As %String [ Private ]
{
	Quit ""
}

Method GetRecipientDescByFacility(pFacility As %String) As %String [ Private ]
{
	Quit pFacility
}

Method GetRecipientDescBySubscription(pSubscription As %String) As %String
{
	Quit pSubscription
}

Method SetFacilityAndHospitalService(ByRef pPatDataArray As %String) As %Status
{
	Set status=$SYSTEM.Status.OK()
	Try {
		Set hospitalSvc = pPatDataArray("HOSPITALSVC")
		If (($Get(hospitalSvc)'="")){
			Set pPatDataArray("FACILITY")=hospitalSvc
			If ($Piece(hospitalSvc,"/",2)'=""){
				Set pPatDataArray("FACILITY")=$Piece(hospitalSvc,"/",2)
			}
		}
		Set pPatDataArray("FACILITYDESC")=##class(CUSTOM.CORE.Util.DataDescriptionLookupAndFormator).GetFacilityDescription(pPatDataArray("FACILITY"))
	}Catch exception{
		Set status=exception.AsStatus()
	}
	Quit status
}

// Commented AA SDT-1651 10/13/2015 - not in use

/*
Method AddNotification(ByRef pDataArray As %String, pDeliveryRequestID As %String = "", Output pNotificationDataRowId As %String) As %Status
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
*/

// Commented AA SDT-1651 10/13/2015 - not in use

/*
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
}*/
}
