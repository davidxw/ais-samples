<xsl:stylesheet xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:math="http://www.w3.org/2005/xpath-functions/math" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:dm="http://azure.workflow.datamapper" xmlns:ef="http://azure.workflow.datamapper.extensions" exclude-result-prefixes="xsl xs math dm ef" version="3.0" expand-text="yes">
  <xsl:output indent="yes" media-type="text/xml" method="xml" />
  <xsl:template match="/">
    <xsl:variable name="xmlinput" select="json-to-xml(/)" />
    <xsl:apply-templates select="$xmlinput" mode="azure.workflow.datamapper" />
  </xsl:template>
  <xsl:template match="/" mode="azure.workflow.datamapper">
    <GT_OutboundOrders>
      <ShipToCustomer>
        <ClientID>{/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentHeader']/*[@key='ShipToParty']/*[@key='ID']}</ClientID>
        <AddressName>{/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentHeader']/*[@key='ShipToParty']/*[@key='Location']/*[@key='Address']/*[@key='Name']}</AddressName>
        <AddressLine1>{/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentHeader']/*[@key='ShipToParty']/*[@key='Location']/*[@key='Address']/*[@key='StreetName']}</AddressLine1>
        <AddressCity>{/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentHeader']/*[@key='ShipToParty']/*[@key='Location']/*[@key='Address']/*[@key='CityName']}</AddressCity>
        <AddressPostalCode>{number(/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentHeader']/*[@key='ShipToParty']/*[@key='Location']/*[@key='Address']/*[@key='PostalCode']) idiv 1}</AddressPostalCode>
        <AddressCountryName>{/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentHeader']/*[@key='ShipToParty']/*[@key='Location']/*[@key='Address']/*[@key='CountryCode']}</AddressCountryName>
      </ShipToCustomer>
      <OrderSegment>
        <ClientID>{/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentHeader']/*[@key='ShipToParty']/*[@key='ID']}</ClientID>
        <xsl:for-each select="/*/*[@key='ProcessShipment']/*[@key='DataArea']/*[@key='Shipment']/*[@key='ShipmentItem']/*">
          <OrderLineSegment>
            <ItemNumber>{number(*[@key='Item']/*[@key='ID']) idiv 1}</ItemNumber>
          </OrderLineSegment>
        </xsl:for-each>
      </OrderSegment>
    </GT_OutboundOrders>
  </xsl:template>
</xsl:stylesheet>