import GzipEncoder "Encoder";
import GzipDecoder "Decoder";
import Header "Header";

import Deflate "../Deflate";

module {
    public type Header = Header.Header;
    public type DeflateOptions = Deflate.DeflateOptions;
    
    public type Encoder = GzipEncoder.Encoder;
    public type Decoder = GzipDecoder.Decoder;

    public type EncodedResponse = GzipEncoder.EncodedResponse;
    public type DecodedResponse = GzipDecoder.DecodedResponse;

    public type EncoderBuilder = GzipEncoder.EncoderBuilder;
    public let EncoderBuilder : () -> GzipEncoder.EncoderBuilder = GzipEncoder.EncoderBuilder;
   
    public let Encoder : (Header.Header, Deflate.DeflateOptions) ->  GzipEncoder.Encoder = GzipEncoder.Encoder;
    public let Decoder : () -> GzipDecoder.Decoder = GzipDecoder.Decoder;

}