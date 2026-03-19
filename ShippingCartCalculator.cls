/*
  This sample is for the situations where Shipping Calculation needs to be extended or overridden
  via the extension point for the Shipping Calculator. The Custom Apex Class must be linked to the
  Shipping Calculator extension point and then the integration must be linked to the webstore via appropriate Setup.
  This class must extend the CartExtension.ShippingCartCalculator class to be processed.
  Referance Documentation: https://developer.salesforce.com/docs/commerce/salesforce-commerce/guide/extension-provider-examples.html#shipping-calculator-example
*/
public class ShippingCartCalculator extends CartExtension.ShippingCartCalculator {

  public virtual override void calculate(CartExtension.CartCalculateCalculatorRequest request) {
    
    CartExtension.Cart cart = request.getCart();
    CartExtension.CartValidationOutputList cartValidationOutputList = cart.getCartValidationOutputs();
    cleanupCartValidationOutputs(cartValidationOutputList);

    // To create the Cart delivery group methods, we need to get the ID of the cart delivery group.
    CartExtension.CartDeliveryGroupList cartDeliveryGroups = cart.getCartDeliveryGroups();
    if (cartDeliveryGroups.size() == 0) {
      addCartValidationOutputMessage('ShippingCartCalculator: No Cart Delivery Groups have been defined', CartExtension.CartValidationOutputLevelEnum.ERROR, cartValidationOutputList);
    } else {
      for (Integer i = (cartDeliveryGroups.size() - 1); i >= 0; i--) {
        CartExtension.CartDeliveryGroup cartDeliveryGroup = cartDeliveryGroups.get(i);
        CartExtension.CartDeliveryGroupMethodList cartDeliveryGroupMethods = cartDeliveryGroup.getCartDeliveryGroupMethods();
        resetCartDeliveryGroupMethods(cartDeliveryGroupMethods, cartDeliveryGroup);

        ShippingCartCalculator_Setting__mdt shippingCartConfig = ShippingCartCalculator_Setting__mdt.getInstance('Default');
        if(shippingCartConfig?.ShippingProductId__c == null) {
          addCartValidationOutputMessage('ShippingCartCalculator: No Shipping Product has been defined', CartExtension.CartValidationOutputLevelEnum.ERROR, cartValidationOutputList);
        } else {
          CartExtension.CartItemList cartItems = cart.getCartItems();
          Map<String, Logistics_Box_Dimension__mdt> logisticsBoxDimensions = Logistics_Box_Dimension__mdt.getAll();
          ThreeDBinPacking_IntegrationService.ThreeDBPResponse optimalBoxes = getOptimalShipmentBoxesFrom3DBPService(logisticsBoxDimensions.values(), cartItems, cartValidationOutputList);
          System.debug('Optimal Boxes from 3DBP Service: ' + optimalBoxes);
          populateCartDeliveryGroupMethod(logisticsBoxDimensions, optimalBoxes, shippingCartConfig, cartDeliveryGroup, cartValidationOutputList);
        }
      }
    }
  }

  private void cleanupCartValidationOutputs(CartExtension.CartValidationOutputList cartValidationOutputList){
    // Clean up CVO based on Shipping
    for (Integer i = (cartValidationOutputList.size() - 1); i >= 0; i--) {
      CartExtension.CartValidationOutput cvo = cartValidationOutputList.get(i);
      if (cvo.getType() == CartExtension.CartValidationOutputTypeEnum.SHIPPING) {
        cartValidationOutputList.remove(cvo);
      }
    }
  }

  private void resetCartDeliveryGroupMethods(CartExtension.CartDeliveryGroupMethodList cartDeliveryGroupMethods, CartExtension.CartDeliveryGroup cartDeliveryGroup){
    // Clean up the CartDeliveryGroupMethods
    for (Integer j = (cartDeliveryGroupMethods.size() - 1); j >= 0; j--) {
      CartExtension.CartDeliveryGroupMethod method = cartDeliveryGroupMethods.get(j);
      cartDeliveryGroupMethods.remove(method);
    }
    // To clear selected Cart Delivery Group Method
    cartDeliveryGroup.setSelectedCartDeliveryGroupMethod(null);
  }

  private ThreeDBinPacking_IntegrationService.ThreeDBPResponse getOptimalShipmentBoxesFrom3DBPService(List<Logistics_Box_Dimension__mdt> boxDimensions, CartExtension.CartItemList cartItems, CartExtension.CartValidationOutputList cartValidationOutputList) {
    List<ThreeDBinPacking_IntegrationService.Bin> bins = createBinListByBoxDimensions(boxDimensions);
    if (bins.size() == 0){
      addCartValidationOutputMessage('ShippingCartCalculator: No Box Dimensions have been defined in the Box Dimension Metadata Type', CartExtension.CartValidationOutputLevelEnum.ERROR, cartValidationOutputList);
      return null;
    }
    List<ThreeDBinPacking_IntegrationService.Item> items = createServiceItemListFromCartItems(cartItems);

    ThreeDBinPacking_IntegrationService.ThreeDBPResponse serviceResponse;
    try{
      serviceResponse = ThreeDBinPacking_IntegrationService.packAShipment(bins, items);
      System.debug('####### 3DBP Service Response: ' + serviceResponse);
      if (serviceResponse.response.errors.size() > 0){ 
          for (ThreeDBinPacking_IntegrationService.Error err : serviceResponse.response.errors){
              String errorMessage = err.level + ' - ' + err.message;
              addCartValidationOutputMessage('ShippingCartCalculator: ' + errorMessage, CartExtension.CartValidationOutputLevelEnum.ERROR, cartValidationOutputList);
          }
          return null;
      }
    }catch(Exception e){
      addCartValidationOutputMessage(e.getMessage(), CartExtension.CartValidationOutputLevelEnum.ERROR, cartValidationOutputList);
    }
    return serviceResponse;
  }

  private List<ThreeDBinPacking_IntegrationService.Bin> createBinListByBoxDimensions(List<Logistics_Box_Dimension__mdt> boxDimensions){
    List<ThreeDBinPacking_IntegrationService.Bin> bins = new List<ThreeDBinPacking_IntegrationService.Bin>();
    for (Logistics_Box_Dimension__mdt boxDimension : boxDimensions){
      ThreeDBinPacking_IntegrationService.Bin bin = new ThreeDBinPacking_IntegrationService.Bin(
        boxDimension.QualifiedApiName, boxDimension.Height_cm__c, boxDimension.Width_cm__c, boxDimension.Length_cm__c
      ); 
      bins.add(bin);
    }
    return bins;
  }

  private List<ThreeDBinPacking_IntegrationService.Item> createServiceItemListFromCartItems(CartExtension.CartItemList cartItems){
    List<ThreeDBinPacking_IntegrationService.Item> serviceitems = new List<ThreeDBinPacking_IntegrationService.Item>();
    Iterator<CartExtension.CartItem> items = cartItems.iterator();
    List<Id> productIds = new List<Id>();
    while(items.hasNext()) {
      CartExtension.CartItem cartItem = items.next();
      if (cartItem.getSku() == null) { //getSKU() method return null for Shipping Product, so we skip that
        continue;
      }
      productIds.add(cartItem.getProduct2Id());
    }

    Map<Id, Product2> productsMap = getProductsMapByIds(productIds);

    items = cartItems.iterator();
    while(items.hasNext()) {
      CartExtension.CartItem cartItem = items.next();
      if (cartItem.getSku() == null) { //getSKU() method return null for Shipping Product, so we skip that
        continue;
      }
      Product2 product = productsMap.get(cartItem.getProduct2Id());

      ThreeDBinPacking_IntegrationService.Item item = new ThreeDBinPacking_IntegrationService.Item(product.StockKeepingUnit, product.Width_cm__c, 
        product.Height_cm__c, product.Length_cm__c, product.ShippingWeight, Integer.valueof(cartItem.getQuantity()), true
      );
      serviceitems.add(item);
    }
    return serviceitems;
  } 

  private void populateCartDeliveryGroupMethod(Map<String, Logistics_Box_Dimension__mdt> logisticsBoxDimensions, ThreeDBinPacking_IntegrationService.ThreeDBPResponse optimalBoxes, ShippingCartCalculator_Setting__mdt shippingCartConfig, CartExtension.CartDeliveryGroup cartDeliveryGroup, CartExtension.CartValidationOutputList cartValidationOutputList){
    /* Set Shipping Instructions*/
    Decimal totalWeight = 0;
    Decimal totalDesiWeight = 0;
    List<String> packingPlans = new List<String>();
    for (ThreeDBinPacking_IntegrationService.BinPacked binPacked : optimalBoxes.response.bins_packed){
      String binDetails = binPacked.bin_data.id + ' ➝ ' + binPacked.bin_data.weight + ' kg / ' + binPacked.items.size() + ' items';

      Map<String, Integer> itemCountMap = new Map<String, Integer>();
      for(ThreeDBinPacking_IntegrationService.ItemData item : binPacked.items){
        itemCountMap.put(item.id, itemCountMap.containsKey(item.id) ? itemCountMap.get(item.id) + 1 : 1);
      }
      binDetails += itemCountMap.toString();
      packingPlans.add(binDetails);

      totalWeight += binPacked.bin_data.weight;
      totalDesiWeight += logisticsBoxDimensions.get(binPacked.bin_data.id).Desi_weight__c;
    }

    packingPlans.add('Total — ' + totalWeight + ' kg / Desi — ' + totalDesiWeight + ' kg');
    String packingPlan = String.join(packingPlans, ' ✦ ');
    cartDeliveryGroup.setShippingInstructions(packingPlan);
    
	  /*Calculate Shipping Fee */
    Decimal chargeableWeight = Math.max(totalWeight, totalDesiWeight);
    String shippingCountryCode = cartDeliveryGroup.getDeliverToAddress().getCountry();
    List<Shipping_Rate__c> shippingRates = getShippingRates(shippingCountryCode, chargeableWeight);
    if (shippingRates.isEmpty()){
      addCartValidationOutputMessage('ShippingCartCalculator: No Shipping Rates have been defined for Country: ' + shippingCountryCode, CartExtension.CartValidationOutputLevelEnum.ERROR, cartValidationOutputList);
      return;
    }
    Integer boxCount = optimalBoxes.response.bins_packed.size();
    CartExtension.CartDeliveryGroupMethodList cartDeliveryGroupMethods = cartDeliveryGroup.getCartDeliveryGroupMethods();
    for (Shipping_Rate__c rate : shippingRates){
      Decimal finalPrice = calculateFinalPrice(rate, chargeableWeight, boxCount, shippingCartConfig);
      String shippingMethodDeliveryName = rate.Service_Type__c + ' : ' + packingPlan;  //rate.Service_Type__c; 
      CartExtension.CartDeliveryGroupMethod newMethod =
      buildCartDeliveryGroupMethod(shippingMethodDeliveryName, finalPrice, shippingCartConfig.ShippingProductId__c, rate);
      cartDeliveryGroupMethods.add(newMethod);
    }
  }
  
  private List<Shipping_Rate__c> getShippingRates(String countryCode, Decimal weight){
    return [
        SELECT Id, Service_Type__c, Weight_Min_Kg__c, Weight_Max_Kg__c,
                Amount__c, Minimum_Rate_Package__c, Is_Over_Weight__c,
                Transit_Min_Days__c, Transit_Max_Days__c, Processing_Time_In_Day__c
        FROM Shipping_Rate__c
        WHERE Country__c = :countryCode
        AND Weight_Min_Kg__c <= :weight
        AND Weight_Max_Kg__c >= :weight
    ];
  }

  private Decimal calculateFinalPrice(Shipping_Rate__c rate, Decimal chargeableWeight, Integer boxCount, ShippingCartCalculator_Setting__mdt config){
    Decimal basePrice = rate.Is_Over_Weight__c ? chargeableWeight * rate.Amount__c : rate.Amount__c;
    if(boxCount > 1){
        Decimal mrp = boxCount * rate.Minimum_Rate_Package__c;
        basePrice = Math.max(basePrice, mrp);
    }
    return (basePrice *
            config.Fuel_Factor__c *
            config.VAT_Factor__c *
            config.Safety_Factor__c).setScale(2);
  }

  private CartExtension.CartDeliveryGroupMethod buildCartDeliveryGroupMethod(String deliveryName, Decimal shippingFee, Id shippingProductId, Shipping_Rate__c shipRate){
      CartExtension.CartDeliveryGroupMethod newMethod = new CartExtension.CartDeliveryGroupMethod(deliveryName, shippingFee, shippingProductId);
      newMethod.setTransitTimeMin(Integer.valueOf(shipRate.Transit_Min_Days__c));
      newMethod.setTransitTimeMax(Integer.valueOf(shipRate.Transit_Max_Days__c));
      newMethod.setTransitTimeUnit(CartExtension.TimeUnitEnum.DAYS);
      newMethod.setProcessTime(Integer.valueOf(shipRate.Processing_Time_In_Day__c));
      newMethod.setProcessTimeUnit(CartExtension.TimeUnitEnum.DAYS);
      return newMethod;
  }

  private Map<Id, Product2> getProductsMapByIds(List<Id> productIds){
    Map<Id, Product2> productsMap = new Map<Id, Product2>();
    for (Product2 product : [SELECT Id, StockKeepingUnit, Height_cm__c, Width_cm__c, Length_cm__c, ShippingWeight FROM Product2 WHERE Id IN :productIds]){
      productsMap.put(product.Id, product);
    }
    return productsMap;
  }

  private void addCartValidationOutputMessage(String message, CartExtension.CartValidationOutputLevelEnum level, CartExtension.CartValidationOutputList cartValidationOutputList) {
    CartExtension.CartValidationOutput cvo = new CartExtension.CartValidationOutput(
      CartExtension.CartValidationOutputTypeEnum.SHIPPING,
      level
    );
    cvo.setMessage(message);
    cartValidationOutputList.add(cvo);
  }
}