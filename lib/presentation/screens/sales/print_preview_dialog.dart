import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:billzo/core/theme/colors.dart';
import 'package:billzo/domain/business/business.dart';
import 'package:billzo/domain/business/business_settings.dart';
import 'package:billzo/domain/invoice/invoice.dart';
import 'package:billzo/domain/party/party.dart';
import 'package:billzo/infrastructure/services/printing/esc_pos_receipt_formatter.dart';
import 'package:billzo/infrastructure/services/printing/printer_service.dart';
import 'package:billzo/presentation/providers/database_providers.dart';

/// Modal dialog for previewing A4 tax invoices and thermal receipts (80mm/58mm/text)
/// before sending them to the Windows print spooler or POS counter printer.
class PrintPreviewDialog extends ConsumerStatefulWidget {
  final Business business;
  final Invoice invoice;
  final Party? customer;
  final BusinessSettings? settings;
  final PrintFormat initialFormat;

  const PrintPreviewDialog({
    super.key,
    required this.business,
    required this.invoice,
    this.customer,
    this.settings,
    this.initialFormat = PrintFormat.a4,
  });

  /// Displays the [PrintPreviewDialog] in a modal window.
  static Future<void> show(
    BuildContext context, {
    required Business business,
    required Invoice invoice,
    Party? customer,
    BusinessSettings? settings,
    PrintFormat initialFormat = PrintFormat.a4,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PrintPreviewDialog(
        business: business,
        invoice: invoice,
        customer: customer,
        settings: settings,
        initialFormat: initialFormat,
      ),
    );
  }

  @override
  ConsumerState<PrintPreviewDialog> createState() => _PrintPreviewDialogState();
}

class _PrintPreviewDialogState extends ConsumerState<PrintPreviewDialog> {
  late PrintFormat _selectedFormat;
  bool _isPlainTextMode = false;

  late bool _showLogo;
  late bool _showBankDetails;
  late bool _showUpiQr;
  bool _kickDrawer = false;

  bool _isProcessing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.initialFormat;
    _showLogo = widget.settings?.printBusinessLogo ?? true;
    _showBankDetails = widget.settings?.printBankDetails ?? true;
    _showUpiQr = widget.settings?.printUpiQr ?? true;
  }

  BusinessSettings _buildEffectiveSettings() {
    final base = widget.settings;
    if (base != null) {
      return base.copyWith(
        printBusinessLogo: _showLogo,
        printBankDetails: _showBankDetails,
        printUpiQr: _showUpiQr,
        thermalPrinterType: _selectedFormat == PrintFormat.thermal58mm ? '58mm' : '80mm',
      );
    }
    return BusinessSettings(
      id: 'temp-settings',
      businessId: widget.business.id,
      printBusinessLogo: _showLogo,
      printBankDetails: _showBankDetails,
      printUpiQr: _showUpiQr,
      thermalPrinterType: _selectedFormat == PrintFormat.thermal58mm ? '58mm' : '80mm',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _handlePrint() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Sending document to print spooler...';
    });

    final printer = ref.read(printerServiceProvider);
    final effectiveSettings = _buildEffectiveSettings();

    try {
      final success = await printer.printInvoice(
        invoice: widget.invoice,
        business: widget.business,
        customer: widget.customer,
        settings: effectiveSettings,
        format: _selectedFormat,
      );

      if (mounted) {
        setState(() {
          _statusMessage = success ? 'Print job submitted successfully.' : 'Printing cancelled or aborted.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Printing error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleSharePdf() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Preparing PDF document...';
    });

    final printer = ref.read(printerServiceProvider);
    final effectiveSettings = _buildEffectiveSettings();

    try {
      await printer.shareInvoicePdf(
        invoice: widget.invoice,
        business: widget.business,
        customer: widget.customer,
        settings: effectiveSettings,
        format: _selectedFormat,
      );
      if (mounted) {
        setState(() => _statusMessage = 'PDF exported.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Export error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleSavePdf() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Saving PDF document...';
    });

    final printer = ref.read(printerServiceProvider);
    final effectiveSettings = _buildEffectiveSettings();

    try {
      final docBytes = await printer.generateInvoiceDocument(
        invoice: widget.invoice,
        business: widget.business,
        customer: widget.customer,
        settings: effectiveSettings,
        format: _selectedFormat,
      );

      // Determine local desktop save directory
      final homeDir = Platform.environment['USERPROFILE'] ?? Directory.current.path;
      final targetDir = Directory('$homeDir${Platform.pathSeparator}Documents');
      final exportPath = targetDir.existsSync()
          ? '${targetDir.path}${Platform.pathSeparator}Invoice_${widget.invoice.invoiceNumber}.pdf'
          : '${Directory.current.path}${Platform.pathSeparator}Invoice_${widget.invoice.invoiceNumber}.pdf';

      final file = await printer.saveInvoicePdfToFile(
        pdfBytes: docBytes,
        targetPath: exportPath,
      );

      if (mounted) {
        setState(() => _statusMessage = 'Saved to: ${file.path}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invoice PDF saved to ${file.path}'),
            backgroundColor: BillzoColors.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Save error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _handleCopyPlainText() async {
    final effectiveSettings = _buildEffectiveSettings();
    final plainText = EscPosReceiptFormatter.formatAsPlainText(
      invoice: widget.invoice,
      business: widget.business,
      customer: widget.customer,
      settings: effectiveSettings,
      format: _selectedFormat == PrintFormat.thermal58mm ? PrintFormat.thermal58mm : PrintFormat.thermal80mm,
    );

    await Clipboard.setData(ClipboardData(text: plainText));

    if (mounted) {
      setState(() => _statusMessage = 'Receipt plain text copied to clipboard.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Receipt text copied to clipboard.'),
          backgroundColor: BillzoColors.darkSlate,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isProcessing) Navigator.of(context).pop();
        },
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
          if (!_isProcessing) _handlePrint();
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: BillzoColors.cardSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header
                _buildHeader(),
                const Divider(height: 1, color: BillzoColors.border),

                // 2. Toolbar (Format selector & Toggle controls)
                _buildToolbar(),
                const Divider(height: 1, color: BillzoColors.border),

                // 3. Document Preview Area
                Expanded(
                  child: _isPlainTextMode ? _buildPlainTextRollPreview() : _buildPdfPreviewArea(),
                ),

                // 4. Status Bar & Action Bar
                const Divider(height: 1, color: BillzoColors.border),
                _buildActionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final custName = widget.customer?.name ?? widget.invoice.customerName ?? 'Walk-in Customer';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BillzoColors.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.print_outlined, color: BillzoColors.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Print Preview: ${widget.invoice.invoiceNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: BillzoColors.darkSlate),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.invoice.status.backgroundColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: widget.invoice.status.color.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          widget.invoice.status.displayName,
                          style: TextStyle(color: widget.invoice.status.color, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Customer: $custName • Total: ₹${widget.invoice.totalAmount.toIndianRupeeString()}',
                    style: const TextStyle(fontSize: 12, color: BillzoColors.neutralText),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20, color: BillzoColors.neutralText),
            tooltip: 'Close (Esc)',
            onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Format selection segmented pills
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Format: ', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: BillzoColors.darkSlate)),
              const SizedBox(width: 6),
              _buildFormatChip(
                label: 'Standard A4',
                icon: Icons.description_outlined,
                isSelected: !_isPlainTextMode && _selectedFormat == PrintFormat.a4,
                onTap: () {
                  setState(() {
                    _isPlainTextMode = false;
                    _selectedFormat = PrintFormat.a4;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildFormatChip(
                label: '80mm POS',
                icon: Icons.receipt_outlined,
                isSelected: !_isPlainTextMode && _selectedFormat == PrintFormat.thermal80mm,
                onTap: () {
                  setState(() {
                    _isPlainTextMode = false;
                    _selectedFormat = PrintFormat.thermal80mm;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildFormatChip(
                label: '58mm POS',
                icon: Icons.receipt_long_outlined,
                isSelected: !_isPlainTextMode && _selectedFormat == PrintFormat.thermal58mm,
                onTap: () {
                  setState(() {
                    _isPlainTextMode = false;
                    _selectedFormat = PrintFormat.thermal58mm;
                  });
                },
              ),
              const SizedBox(width: 6),
              _buildFormatChip(
                label: 'Text Receipt',
                icon: Icons.text_snippet_outlined,
                isSelected: _isPlainTextMode,
                onTap: () {
                  setState(() {
                    _isPlainTextMode = true;
                  });
                },
              ),
            ],
          ),

          // Toggles
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilterChip(
                label: const Text('Logo', style: TextStyle(fontSize: 11.5)),
                selected: _showLogo,
                onSelected: (val) => setState(() => _showLogo = val),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('Bank Info', style: TextStyle(fontSize: 11.5)),
                selected: _showBankDetails,
                onSelected: (val) => setState(() => _showBankDetails = val),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              FilterChip(
                label: const Text('UPI QR', style: TextStyle(fontSize: 11.5)),
                selected: _showUpiQr,
                onSelected: (val) => setState(() => _showUpiQr = val),
                visualDensity: VisualDensity.compact,
              ),
              if (_selectedFormat != PrintFormat.a4) ...[
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Open Drawer', style: TextStyle(fontSize: 11.5)),
                  selected: _kickDrawer,
                  onSelected: (val) => setState(() => _kickDrawer = val),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormatChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? BillzoColors.primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? BillzoColors.primaryBlue : BillzoColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : BillzoColors.darkSlate),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : BillzoColors.darkSlate,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfPreviewArea() {
    final printer = ref.read(printerServiceProvider);
    final effectiveSettings = _buildEffectiveSettings();

    return Container(
      color: const Color(0xFFF1F5F9),
      child: PdfPreview(
        build: (format) async {
          return await printer.generateInvoiceDocument(
            invoice: widget.invoice,
            business: widget.business,
            customer: widget.customer,
            settings: effectiveSettings,
            format: _selectedFormat,
          );
        },
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        maxPageWidth: _selectedFormat == PrintFormat.a4 ? 680 : 380,
        previewPageMargin: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        loadingWidget: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Rendering vector invoice...', style: TextStyle(fontSize: 12, color: BillzoColors.neutralText)),
            ],
          ),
        ),
        onError: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 36, color: BillzoColors.dangerRed),
                const SizedBox(height: 12),
                Text('Preview generation failed: $error', style: const TextStyle(fontSize: 13, color: BillzoColors.darkSlate)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlainTextRollPreview() {
    final effectiveSettings = _buildEffectiveSettings();
    final plainText = EscPosReceiptFormatter.formatAsPlainText(
      invoice: widget.invoice,
      business: widget.business,
      customer: widget.customer,
      settings: effectiveSettings,
      format: _selectedFormat == PrintFormat.thermal58mm ? PrintFormat.thermal58mm : PrintFormat.thermal80mm,
    );

    return Container(
      color: const Color(0xFFE2E8F0),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: _selectedFormat == PrintFormat.thermal58mm ? 360 : 480,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF8),
            borderRadius: BorderRadius.circular(4),
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 10, offset: Offset(0, 4)),
            ],
            border: Border.all(color: const Color(0xFFE2D9CC)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('POS RECEIPT ROLL', style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: Colors.black45)),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy Plain Text',
                    onPressed: _handleCopyPlainText,
                  ),
                ],
              ),
              const Divider(color: Color(0xFFE2D9CC)),
              SelectableText(
                plainText,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Status indicator or notice
          Expanded(
            child: Row(
              children: [
                if (_isProcessing) ...[
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _statusMessage ?? 'Ready to print. (Ctrl+P to print, Esc to close)',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _statusMessage != null &&
                              (_statusMessage!.contains('error') || _statusMessage!.contains('failed'))
                          ? BillzoColors.dangerRed
                          : BillzoColors.neutralText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons
          Row(
            children: [
              TextButton(
                onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              const SizedBox(width: 8),

              if (_isPlainTextMode) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Text'),
                  onPressed: _isProcessing ? null : _handleCopyPlainText,
                ),
                const SizedBox(width: 8),
              ],

              OutlinedButton.icon(
                icon: const Icon(Icons.save_alt, size: 16),
                label: const Text('Save PDF'),
                onPressed: _isProcessing ? null : _handleSavePdf,
              ),
              const SizedBox(width: 8),

              OutlinedButton.icon(
                icon: const Icon(Icons.share_outlined, size: 16),
                label: const Text('Share'),
                onPressed: _isProcessing ? null : _handleSharePdf,
              ),
              const SizedBox(width: 8),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BillzoColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                icon: const Icon(Icons.print, size: 17),
                label: const Text('Print (Ctrl+P)', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: _isProcessing ? null : _handlePrint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
