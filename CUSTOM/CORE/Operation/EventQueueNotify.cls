Class CUSTOM.CORE.Operation.EventQueueNotify Extends (Ens.BusinessOperation, HS.Util.XSLTTransformer)
{

Property BusEventQueueNotifyClient As Ens.DataType.ConfigName [ InitialExpression = "ToBusEventQueue" ];

Property XSLTransform As %String [ InitialExpression = "SDA3/Custom/OmitXMLDeclaration.xsl" ];

Property InfoTypes As %String [ InitialExpression = "ALG,ART,DXG,LAB,MED,OBS,PRB,RAD,VXU,OTH,HIS,FAM,SOC,ADV,APT,CLINREL,PEX,PRC,PROGRAM" ];

// To be passed by the child class.

Property SourceAppName As %String;

// To be passed by the child class. Only Two values allowed. ("major"/"minor")

Property QueueEventType As %String;

// To be passed by the child class. Used for passing the Routing key.

Property QueueName As %String;

// Can be passed by the child class. 

Property EventDescription As %String;

Parameter SETTINGS As %String = "BusEventQueueNotifyClient,InfoTypes";

/// This operation will be trigerred by the susbscription and will be responsible to pull the patient level SDA and also to create the 
/// Payload. It will also create the SOAP request as needed by the Rabbit MQ and send to the client operation.
XData MessageMap
{
<MapItems>
	<MapItem MessageType="HS.Message.Push.DeliveryRequest"> 
		<Method>HandleDeliveryRequest</Method>
	</MapItem>
</MapItems>
}

Method HandleDeliveryRequest(pRequest As HS.Message.Push.DeliveryRequest, ByRef pResponse As HS.Message.Push.DeliveryResponse) As %Status
{
	Set status=$System.Status.OK()
	Set pResponse=##class(HS.Message.Push.DeliveryResponse).%New()
	Set pResponse.OKToPurge=1
	
	Try {
		Do ..ExtractData(pRequest.XMLData, pRequest.MPIID, pRequest.Subscription.Subject)
	}
	Catch(exception){
		Set status=exception.AsStatus()
		$$$LOGERROR($SYSTEM.Status.GetErrorText(status))
	}
	Quit status
}

// get values from XMLData stream needed to create EventQueueRequest

Method ExtractData(pStream As %Stream, tMPIID As %String, pSubscriptionName As %String, Output pSC As %Status) As %Boolean
{
	set pSC=$$$OK
	set tReqInfoType = ""
	try {
		//Initialize
		set (tMRN,tAA,tEncNum)=""
	
		//Get MRN and AA using SDA Helper utils
		Set tSDADataHelper=##class(CUSTOM.CORE.Util.SDADataHelper).%New()
		Set tSDADataHelper.pSDAStream=pStream

		Set tMRN=tSDADataHelper.GetMRNFromSDA()
		if tMRN=""
		{
			Set pSC=$$$NOTOK
			$$$LOGERROR("MRN not found")
			quit:$$$ISERR(pSC)
		}
		Set tAA=tSDADataHelper.GetAssigningAuthorityFromSDA()
		if tAA=""
		{
			Set pSC=$$$NOTOK
			$$$LOGERROR("AssigningAuthority not found")
			quit:$$$ISERR(pSC)
		}
		
		//Get Event Type - If event description comes from  the child class use, else get it from SDA
		If (..EventDescription '=""){
			Set tEventDescription = ..EventDescription
		}Else{
			Set tEventDescription = tSDADataHelper.GetEventTypeFromSDA()
		}
		Set tQueueEventType = ..GetQueueEventType(pStream)		
		If ( $ZCVT(tQueueEventType,"U")= "MAJOR"){
			//Get patient level SDA using utils	for major event types	
			//Default includes PAT infotype
			Set tInfoTypes = ..InfoTypes		
		
			Set objSdaDataHelper = ##class(CUSTOM.CORE.Util.SDADataHelper).%New()
			//make the call to fetch the complete SDA with HSAA_1 late binding profile.
			Set tSC = objSdaDataHelper.GetSDAByMRNWithPatientFilterLateBindingExtended(tMRN,tAA,"",tInfoTypes,0,1,"HSAA_1")

			//If no SDA found, also error
			Set tSource = objSdaDataHelper.pSDAStream
			Do tSource.Rewind()
		}Else{
			//Set the transactional SDA for minor events.
			Set tSource = pStream
		}
		
		//Perform Transformation on the SDA and remove the XML declaration.
		#dim tTarget As %Stream
		Set pSC = ..Transform(tSource, ..XSLTransform , .tTarget, .tParams) $$$ThrowOnError(pSC)

		If tTarget.SizeGet() > 0 {
			//Create the EventQueueRequest
			Set pSC=..CreateEventQueueRequest(tMPIID, tMRN, tAA, tEventDescription, tTarget)
		}
		else {
			$$$ThrowStatus($$$ERROR($$$GeneralError, "No SDA Found for MRN:"_tMRN))
		} 
		quit:$$$ISERR(pSC)
		
	} catch (e) {
		set pSC=e.AsStatus()
		$$$LOGERROR($SYSTEM.Status.GetErrorText(pSC))
	}
	
	quit pSC
}

/// Create EventQueueRequest 
Method CreateEventQueueRequest(pMPIID As %String, pMRN As %String, pAA As %String, pEventDescription As %String, pStream As %Stream = "") As %Status
{
	set tSC=$$$OK
	try {
		
		$$$TRACE("Generating & sending event for event description: "_pEventDescription)
		
		//Build the payload to be embedded in the Request.
		Set tEventQueuePayloadMessage=##class(CUSTOM.Util.Message.EventQueuePayloadMessage).%New()	

		set tEventQueuePayloadMessage.EventType= $ZCVT(..QueueEventType,"W")
		set tEventQueuePayloadMessage.MPIID=pMPIID
		set tEventQueuePayloadMessage.EventDescription=pEventDescription //<Notification EventType>		
		set tEventQueuePayloadMessage.SDA=pStream
		//Export the message into a global stream array.
		Set tSC = tEventQueuePayloadMessage.XMLExportToStream(.tResponseStream) Quit:('tSC)		

		//Build the Request		
		Set tEventQueueRequest = ##Class(CUSTOM.Util.Message.MajorMinorQueuePublishRequest).%New()
		Set tSourceAppName = ..GetSourceAppName(pStream)
		Set tEventQueueRequest.SourceApplication = tSourceAppName
		Set tEventQueueRequest.QueueName = ..GetQueueName(pStream)
		Set tEventQueueRequest.ObjectType = $CLASSNAME(tEventQueuePayloadMessage)
		Set tEventQueueRequest.Payload = tResponseStream
		//Build the object for response
		Set tEventQueueResponse = ##Class(CUSTOM.Util.Message.MajorMinorQueuePublishResponse).%New()	
		//Send Request to the client operation.
		Set tSC=..SendRequestSync(..BusEventQueueNotifyClient,tEventQueueRequest,.tEventQueueResponse)
		//Record Event Queue info for Metric Data database
		Set tSC=..RecordEventQueueMetricData(tEventQueueRequest,tEventQueuePayloadMessage, pMRN, pAA)
		quit:$$$ISERR(tSC)		
	} catch(e) { 
		set tSC=e.AsStatus()
	}
	quit tSC
}

// To be populated by the child class

Method GetQueueEventType(pStream As %Stream) As %String
{
 	Quit ..QueueEventType
}

// To be populated by the child class

Method GetSourceAppName(pStream As %Stream) As %String
{
 	Quit ..SourceAppName
}

// To be populated by the child class

Method GetQueueName(pStream As %Stream) As %String
{
 	Quit ..QueueName
}

Method RecordEventQueueMetricData(pEventQueue As Ens.Request, pEventQueuePayload As Ens.Request, pMRN As %String, pAssigningAuthority As %String) As %Status
{
	set zSC=$$$OK
	try {
		// Extract values from request into string array
		set tEventQueueData("EventType")=pEventQueuePayload.EventType
		set tEventQueueData("MPIID")=pEventQueuePayload.MPIID
		set tEventQueueData("MRN")=pMRN
		set tEventQueueData("AssigningAuthority")=pAssigningAuthority
		set tEventQueueData("EventDescription")=pEventQueuePayload.EventDescription
		set tEventQueueData("SourceApplication")=pEventQueue.SourceApplication
		set tEventQueueData("QueueName")=pEventQueue.QueueName
		set tEventQueueData("ObjectType")=pEventQueue.ObjectType
		
		// Insert into metric data table
		set zSC=##class(CUSTOM.CORE.Metrics.EventQueueMetricData).InsertData(.tEventQueueData) 
		quit:$$$ISERR(zSC)
	} catch(e) { 
		set zSC=e.AsStatus()
	}
	quit zSC
}

}
