import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  bool isProcessing = false;

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String annualPrice,
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
              child: const Text("MOST POPULAR",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ),
          Text(title,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(price,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(annualPrice,
                  style: const TextStyle(color: Colors.white54, fontSize: 14)),
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
              child: const Text("Upgrade Now",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
          const SizedBox(height: 32),
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
            "Unlock Visual Lookbook and Cinematic Reels by upgrading to Infinite Brain.",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
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
                    price: "\$19.99/mo",
                    annualPrice: "or \$200/yr",
                    color: const Color(0xFF3B82F6),
                    onTap: () async {
                      setState(() {
                        isProcessing = true;
                      });
                      try {
                        if (!await Purchases.isConfigured) {
                          debugPrint("ℹ️ MOCK PURCHASE: RevenueCat is not configured on this platform. Simulating successful sandbox checkout UI.");
                          if (context.mounted) Navigator.pop(context);
                          return;
                        }
                        Offerings offerings = await Purchases.getOfferings();
                        Offering? defaultOffering = offerings.current;
                        if (defaultOffering == null) {
                          debugPrint("❌ CRITICAL DIAGNOSTIC: RevenueCat 'current' offering is NULL. Check your offering setup in the dashboard.");
                          return;
                        }
                        Package? creationPackage;
                        for (var pkg in defaultOffering.availablePackages) {
                          if (pkg.storeProduct.identifier == 'axiom_creation_engine_monthly') {
                            creationPackage = pkg;
                            break;
                          }
                        }
                        if (creationPackage != null) {
                          await Purchases.purchasePackage(creationPackage);
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          debugPrint("❌ Product mapping failure: axiom_creation_engine_monthly not found in packages.");
                        }
                      } catch (e) {
                        debugPrint("❌ TESTFLIGHT SUBSCRIPTION ERROR: $e");
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 5),
                              content: Text("Apple StoreKit Alert: ${e.toString()}"),
                            ),
                          );
                        }
                      } finally {
                        setState(() {
                          isProcessing = false;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildPricingCard(
                    title: "Infinite Brain",
                    price: "\$49.99/mo",
                    annualPrice: "or \$450/yr",
                    color: const Color(0xFFA78BFA),
                    isPopular: true,
                    onTap: () async {
                      setState(() {
                        isProcessing = true;
                      });
                      try {
                        if (!await Purchases.isConfigured) {
                          debugPrint("ℹ️ MOCK PURCHASE: RevenueCat is not configured on this platform. Simulating successful sandbox checkout UI.");
                          if (context.mounted) Navigator.pop(context);
                          return;
                        }
                        Offerings offerings = await Purchases.getOfferings();
                        Offering? defaultOffering = offerings.current;
                        if (defaultOffering == null) {
                          debugPrint("❌ CRITICAL DIAGNOSTIC: RevenueCat 'current' offering is NULL. Check your offering setup in the dashboard.");
                          return;
                        }
                        Package? infinitePackage;
                        for (var pkg in defaultOffering.availablePackages) {
                          if (pkg.storeProduct.identifier == 'axiom_infinite_brain_monthly') {
                            infinitePackage = pkg;
                            break;
                          }
                        }
                        if (infinitePackage != null) {
                          await Purchases.purchasePackage(infinitePackage);
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          debugPrint("❌ Product mapping failure: axiom_infinite_brain_monthly not found in packages.");
                        }
                      } catch (e) {
                        debugPrint("❌ TESTFLIGHT SUBSCRIPTION ERROR: $e");
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.redAccent,
                              duration: const Duration(seconds: 5),
                              content: Text("Apple StoreKit Alert: ${e.toString()}"),
                            ),
                          );
                        }
                      } finally {
                        setState(() {
                          isProcessing = false;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 32),
                  GestureDetector(
                    onTap: () async {
                      final Uri emailUri = Uri.parse('mailto:mithilpatel140@gmail.com?subject=Axiom%20Enterprise%20Nexus%20Inquiry');
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
                          Icon(Icons.business_center_outlined,
                              color: Colors.white54, size: 32),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Enterprise Nexus",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                SizedBox(height: 4),
                                Text(
                                    "Contact us for custom scaling and deployment.",
                                    style: TextStyle(
                                        color: Colors.white54, fontSize: 14)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              color: Colors.white38, size: 16),
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
