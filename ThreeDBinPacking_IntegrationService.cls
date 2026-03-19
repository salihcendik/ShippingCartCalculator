/**
    Integration Service for 3D Bin Packing API
    Referance: https://www.3dbinpacking.com/en/api-doc#pack-a-shipment
*/
public with sharing class ThreeDBinPacking_IntegrationService {

    private static final String API_URL = 'callout:ThreeDBinPacking_Integration';

    /**
    Use Pack a Shipment tool to optimize your packing - by number of boxes, space utilization or cost.
    optimization_mode: bins_number [default]
    */
    public static ThreeDBPResponse packAShipment(List<Bin> bins, List<Item> items) {
        ThreeDBinPacking_API_Setting__mdt cfg = ThreeDBinPacking_API_Setting__mdt.getInstance('Default');
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        String endpointUrl = API_URL + '/packIntoMany';
        request.setEndpoint(endpointUrl);
        request.setMethod('GET');
        request.setHeader('Content-Type', 'application/json');
        String jsonBody = JSON.serialize(new ThreeDBPRequest(cfg.username__c, cfg.api_key__c, bins, items));
        //System.debug('3DBP Request Body: ' + jsonBody);
        request.setBody(jsonBody);
        HttpResponse response = http.send(request);
        ThreeDBPResponse result = (ThreeDBPResponse) JSON.deserialize(response.getBody(), ThreeDBPResponse.class);
        return result;
    }

    

    // Request Classes
    public class ThreeDBPRequest{
        public String username;
        public String api_key;
        public List<Item> items;
        public List<Bin> bins;
        public ThreeDBPRequest(String username, String api_key, List<Bin> bins, List<Item> items){
            this.username = username;
            this.api_key = api_key;
            this.bins = bins;
            this.items = items;
        }
    }
    public class Item{
        public String id;
        public Decimal w;
        public Decimal h;
        public Decimal d;
        public Decimal wg;
        public Integer q;
        public Boolean vr;
        public Item(String id, Decimal width, Decimal height, Decimal depth, Decimal weight, Integer quantity, Boolean canRotate){
            this.id = id;
            this.w = width;
            this.h = height;
            this.d = depth;
            this.wg = weight;
            this.q = quantity;
            this.vr = canRotate;
        }
    }
    public class Bin{
        public String id;
        public Decimal h;
        public Decimal w;
        public Decimal d;
        public Decimal max_wg;
        public Bin(String id, Decimal height, Decimal width, Decimal depth){
            this.id = id;
            this.h = height;
            this.w = width;
            this.d = depth;
            this.max_wg = 70; // Default max weight 70 kg
        }
    } 

    // Response Classes
    public class ThreeDBPResponse{
        public Response response;
    }
    public class Response{
        public String id;
        public List<BinPacked> bins_packed;
        public List<Error> errors;
    }
    public class BinPacked{
        public BinData bin_data;
        public List<ItemData> items;
    }
    public class BinData{
        public String id;
        public Decimal weight;
    }
    public class ItemData{
        public String id;
        public Decimal w;
        public Decimal h;
        public Decimal d;
        public Decimal wg;
    }
    public class Error{
        public String level;
        public String message;
    }
}