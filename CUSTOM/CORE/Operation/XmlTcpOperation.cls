Class CUSTOM.CORE.Operation.XmlTcpOperation Extends Ens.BusinessOperation [ ProcedureBlock, System = 4 ]
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
	Set tSC = ..Adapter.SendMessageXMLObj(pRequest, pResponse) 
	Quit tSC
}

}
