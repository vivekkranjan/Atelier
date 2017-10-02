Class CUSTOM.CORE.Operation.XmlObjectTcpOperation Extends Ens.BusinessOperation [ ProcedureBlock ]
{

Parameter ADAPTER = "EnsLib.TCP.CountedXMLOutboundAdapter";

/// Name to transmit as the name of the stream content. May include timestamp specifiers. The %f specifier if present will be 
/// replaced with the name of the stream's original source filename (stripped of characters illegal in target filenames).<p>
/// See the method Ens.Util.File.CreateTimestamp() for documentation of timestamping options.<p>
/// If empty, the stream content will be sent as a single counted block without any associated stream name.
Property Streamname As %String(MAXLEN = 1000) [ InitialExpression = "%f" ];

Parameter SETTINGS As %String = "Streamname:Connection";

Method OnMessage(pRequest As Ens.StreamContainer, Output pResponse As %Persistent) As %Status
{
	Try {
		//Set tSC = ..Adapter.SendMessageXMLObj(pRequest,pResponse,"%RegisteredObject")
		Set tSC = ..SendStreamContainerAsXMLObj(pRequest,pResponse)
	}
	Catch eException {
		Set tSC = eException.AsStatus()
		$$$LOGINFO("Error"_$zcvt($system.Status.GetErrorText(tSC),"O","XML"))
	}
	
	Quit tSC
}

Method SendStreamContainerAsXMLObj(pRequest As Ens.StreamContainer, Output pResponse As %RegisteredObject) As %Status
{
	Try {

		//convert stream container data into xml object using XML reader code
		set tXMLReader = ##class(%XML.Reader).%New()
		set tSC = tXMLReader.OpenStream(pRequest.Stream)
		if $$$ISERR(tSC) $$$ThrowStatus(tSC)
		
		
		set tMessageClass = "HS.Message.XMLMessage"
		set tRootElement = "XMLMessage"
		
		$$$TRACE("Xml root, class: "_tRootElement_", "_tMessageClass)
		do tXMLReader.Correlate(tRootElement,tMessageClass)
		
		//Create XML object to process container data
		while tXMLReader.Next(.tXMLContainer,.tSC)
		{
			//send to adapter to transmit
			set ..Adapter.GetReply = 0
			set tSC = ..Adapter.SendMessageXMLObj(tXMLContainer, .pResponse, "%RegisteredObject")
		}
		
	} Catch(ex) {
		Set tSC = ex.AsStatus()
		$$$LOGERROR("IHE Archive XML TCP operation "_..%ConfigName_" failed to message: error "_$SYSTEM.Status.GetErrorText(tSC))
	}
	
	quit tSC
}

}
