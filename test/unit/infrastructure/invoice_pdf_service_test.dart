import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/invoice/invoice_item.dart';
import 'package:billzo/domain/invoice/invoice_status.dart';
import 'package:billzo/domain/invoice/invoice_type.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/pdf/invoice_pdf_service.dart';

void main() {
  group('InvoicePdfService', () {
    test('generateA4InvoicePdf succeeds or fails with Helvetica font', () async {
      final business = Business(
        id: 'biz-1',
        name: 'Billzo Tech Solutions',
        legalName: 'Billzo Tech Solutions Pvt Ltd',
        tradeName: 'Billzo Tech',
        gstin: '27AABCU9603R1ZM',
        pan: 'AABCU9603R',
        phone: '9876543210',
        email: 'info@billzo.com',
        addressLine1: '123 MG Road',
        city: 'Mumbai',
        stateCode: '27',
        stateName: 'Maharashtra',
        upiId: 'billzo@okaxis',
        bankAccountName: 'Billzo Tech Solutions',
        bankAccountNumber: '98765432101234',
        bankIfsc: 'HDFC0000123',
        bankName: 'HDFC Bank',
        bankBranch: 'Fort, Mumbai',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final customer = Party(
        id: 'cust-1',
        businessId: 'biz-1',
        name: 'Apex Enterprises',
        companyName: 'Apex Enterprises LLP',
        phone: '9123456780',
        email: 'accounts@apex.com',
        gstin: '27XYZAB1234C1Z5',
        billingAddressLine1: '456 Business Park',
        billingCity: 'Pune',
        billingStateCode: '27',
        billingStateName: 'Maharashtra',
        shippingStateCode: '27',
        shippingStateName: 'Maharashtra',
        partyType: PartyType.customer,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final item = InvoiceItem(
        id: 'item-1',
        invoiceId: 'inv-1',
        productId: 'prod-1',
        taxRateId: 'tax-1',
        productName: 'ERP Software License',
        hsnSac: '997331',
        quantityScaled: 1000,
        unitCode: 'PCS',
        ratePaise: 100000,
        taxableAmountPaise: 100000,
        cgstRateBasisPoints: 900,
        cgstAmountPaise: 9000,
        sgstRateBasisPoints: 900,
        sgstAmountPaise: 9000,
        igstRateBasisPoints: 0,
        igstAmountPaise: 0,
        cessRateBasisPoints: 0,
        cessAmountPaise: 0,
        totalAmountPaise: 118000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final invoice = Invoice(
        id: 'inv-1',
        businessId: 'biz-1',
        customerId: 'cust-1',
        customerName: 'Apex Enterprises',
        customerPhone: '9123456780',
        customerGstin: '27XYZAB1234C1Z5',
        invoiceNumber: 'INV-2026-0001',
        invoiceDate: DateTime(2026, 10, 3),
        dueDate: DateTime(2026, 10, 18),
        placeOfSupplyStateCode: '27',
        invoiceType: InvoiceType.taxInvoice,
        status: InvoiceStatus.finalized,
        subtotalPaise: 100000,
        discountPaise: 0,
        taxableAmountPaise: 100000,
        cgstPaise: 9000,
        sgstPaise: 9000,
        igstPaise: 0,
        cessPaise: 0,
        roundOffPaise: 0,
        totalAmountPaise: 118000,
        paidAmountPaise: 0,
        balanceAmountPaise: 118000,
        items: [item],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final bytes = await InvoicePdfService.generateA4InvoicePdf(
        invoice: invoice,
        business: business,
        customer: customer,
        settings: BusinessSettings(
          id: 'set-1',
          businessId: 'biz-1',
          printBusinessLogo: true,
          printBankDetails: true,
          printUpiQr: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });

    test('pw.SvgImage can render vector Rupee symbol in PDF without font dependency', () async {
      final pdf = pw.Document();
      const rupeeSvg = '''
<svg viewBox="0 0 24 24" width="12" height="12" xmlns="http://www.w3.org/2000/svg">
  <path d="M6 3h12v2h-4.5c.8 1.1 1.3 2.5 1.4 4H18v2h-3.1c-.5 3.3-3.2 5.8-6.9 6h-.5l6.5 7h-2.9L5 17v-2h3c2.4 0 4.4-1.6 4.9-3.8H6V9.2h6.8c-.3-1.3-1.4-2.2-2.8-2.2H6V3z" fill="#0F172A"/>
</svg>
''';
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) => pw.Row(
            children: [
              pw.SvgImage(svg: rupeeSvg, width: 10, height: 10),
              pw.SizedBox(width: 4),
              pw.Text('1,250.00'),
            ],
          ),
        ),
      );
      final bytes = await pdf.save();
      expect(bytes, isNotEmpty);
    });
  });
}
