import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  bool isProcessing = false;
  bool isAnnualBilling = false; // Controls sliding state matrix toggle

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String billingPeriodText,
    required Color color,
    bool isPopular = false,
    VoidCallback? onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPopular)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "MOST POPULAR",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                price,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                billingPeriodText,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "Upgrade Now",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Elevate Your Mind",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Unlock Visual Lookbook and Cinematic Reels by upgrading to your Second Brain ecosystem tiers.",
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),

          // Sliding Toggle Mechanism supporting all 4 App Store items
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => isAnnualBilling = false);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: !isAnnualBilling
                            ? const Color(0xFF1E293B)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "Monthly",
                        style: TextStyle(
                          color: !isAnnualBilling
                              ? Colors.white
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => isAnnualBilling = true);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isAnnualBilling
                            ? const Color(0xFFA78BFA)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(
                            "Annual",
                            style: TextStyle(
                              color: isAnnualBilling
                                  ? Colors.black
                                  : Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              "SAVE",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          if (isProcessing)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFA78BFA)),
              ),
            )
          else
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildPricingCard(
                    title: "Creation Engine",
                    price: isAnnualBilling ? "\$16.66/mo" : "\$19.99/mo",
                    billingPeriodText: isAnnualBilling
                        ? "billed annually (\$200/yr)"
                        : "billed monthly",
                    color: const Color(0xFF3B82F6),
                    onTap: () async {
                      setState(() => isProcessing = true);
                      try {
                        if (!await Purchases.isConfigured) {
                          debugPrint(
                            "ℹ️ MOCK PURCHASE: Simulating checkout UI.",
                          );
                          if (context.mounted) Navigator.pop(context);
                          return;
                        }
                        Offerings offerings = await Purchases.getOfferings();
                        Offering? defaultOffering = offerings.current;
                        if (defaultOffering == null) {
                          throw Exception("RevenueCat 'Current Offering' is null. Ensure your main paywall structure toggle is checked 'Set as Current' inside your web catalog console dashboard.");
                        }

                        final String targetProductId = isAnnualBilling
                            ? 'axiom_creation_engine_yearly'
                            : 'axiom_creation_engine_monthly';

                        Package? targetPackage;
                        for (var pkg in defaultOffering.availablePackages) {
                          if (pkg.storeProduct.identifier == targetProductId) {
                            targetPackage = pkg;
                            break;
                          }
                        }

                        if (targetPackage != null) {
                          await Purchases.purchase(
                            PurchaseParams.package(targetPackage),
                          );
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          throw Exception(
                            "Product identifier '$targetProductId' not synced in offerings.",
                          );
                        }
                      } catch (e) {
                        final errorString = e.toString();
                        bool isUserCancelled = errorString.contains('PURCHASE_CANCELLED') || 
                                           errorString.contains('Purchase was cancelled') || 
                                           errorString.contains('userCancelled: true');

                        if (isUserCancelled) {
                          debugPrint("ℹ️ Transaction gracefully cancelled by user session.");
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Colors.amber,
                                duration: Duration(seconds: 2),
                                content: Text("Purchase cancelled."),
                              ),
                            );
                          }
                          setState(() => isProcessing = false);
                          return;
                        }
                        
                        debugPrint("❌ STOREKIT RUNTIME EXCEPTION: $e");
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 6),
                              content: Text(
                                "Apple StoreKit Alert: ${e.toString()}",
                              ),
                            ),
                          );
                        }
                      } finally {
                        setState(() => isProcessing = false);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildPricingCard(
                    title: "Infinite Brain",
                    price: isAnnualBilling ? "\$37.50/mo" : "\$49.99/mo",
                    billingPeriodText: isAnnualBilling
                        ? "billed annually (\$450/yr)"
                        : "billed monthly",
                    color: const Color(0xFFA78BFA),
                    isPopular: true,
                    onTap: () async {
                      setState(() => isProcessing = true);
                      try {
                        if (!await Purchases.isConfigured) {
                          debugPrint(
                            "ℹ️ MOCK PURCHASE: Simulating checkout UI.",
                          );
                          if (context.mounted) Navigator.pop(context);
                          return;
                        }
                        Offerings offerings = await Purchases.getOfferings();
                        Offering? defaultOffering = offerings.current;
                        if (defaultOffering == null) {
                          throw Exception("RevenueCat 'Current Offering' is null. Ensure your main paywall structure toggle is checked 'Set as Current' inside your web catalog console dashboard.");
                        }

                        final String targetProductId = isAnnualBilling
                            ? 'axiom_infinite_brain_yearly'
                            : 'axiom_infinite_brain_monthly';

                        Package? targetPackage;
                        for (var pkg in defaultOffering.availablePackages) {
                          if (pkg.storeProduct.identifier == targetProductId) {
                            targetPackage = pkg;
                            break;
                          }
                        }

                        if (targetPackage != null) {
                          await Purchases.purchase(
                            PurchaseParams.package(targetPackage),
                          );
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          throw Exception(
                            "Product identifier '$targetProductId' not synced in offerings.",
                          );
                        }
                      } catch (e) {
                        final errorString = e.toString();
                        bool isUserCancelled = errorString.contains('PURCHASE_CANCELLED') || 
                                           errorString.contains('Purchase was cancelled') || 
                                           errorString.contains('userCancelled: true');

                        if (isUserCancelled) {
                          debugPrint("ℹ️ Transaction gracefully cancelled by user session.");
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Colors.amber,
                                duration: Duration(seconds: 2),
                                content: Text("Purchase cancelled."),
                              ),
                            );
                          }
                          setState(() => isProcessing = false);
                          return;
                        }
                        
                        debugPrint("❌ STOREKIT RUNTIME EXCEPTION: $e");
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 6),
                              content: Text(
                                "Apple StoreKit Alert: ${e.toString()}",
                              ),
                            ),
                          );
                        }
                      } finally {
                        setState(() => isProcessing = false);
                      }
                    },
                  ),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: () async {
                      final Uri emailUri = Uri.parse(
                        'mailto:mithilpatel140@gmail.com?subject=Axiom%20Enterprise%20Nexus%20Inquiry',
                      );
                      if (await canLaunchUrl(emailUri)) {
                        await launchUrl(emailUri);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.business_center_outlined,
                            color: Colors.white54,
                            size: 32,
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Enterprise Nexus",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Contact us for custom scaling and deployment.",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white38,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
