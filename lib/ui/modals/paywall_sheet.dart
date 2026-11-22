import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  bool isProcessing = false;
  bool isAnnualBilling = false; // Controls sliding state matrix toggle
  Offerings? _offerings;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  Future<void> _fetchOfferings() async {
    try {
      if (await Purchases.isConfigured) {
        final offerings = await Purchases.getOfferings();
        if (mounted) {
          setState(() {
            _offerings = offerings;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching RevenueCat offerings: $e");
    }
  }

  Package? _findPackage(String productId) {
    final available = _offerings?.current?.availablePackages ?? [];
    for (var pkg in available) {
      if (pkg.storeProduct.identifier == productId) {
        return pkg;
      }
    }
    return null;
  }

  Future<void> _executePurchase(String targetProductId) async {
    setState(() => isProcessing = true);
    try {
      if (!await Purchases.isConfigured) {
        debugPrint("ℹ️ MOCK PURCHASE: Purchases not configured.");
        if (mounted) Navigator.pop(context);
        return;
      }

      final pkg = _findPackage(targetProductId);
      if (pkg == null) {
        // Fallback: try fetching fresh offerings
        final offerings = await Purchases.getOfferings();
        final current = offerings.current;
        Package? target;
        if (current != null) {
          for (var p in current.availablePackages) {
            if (p.storeProduct.identifier == targetProductId) {
              target = p;
              break;
            }
          }
        }
        if (target == null) {
          throw Exception("Product '$targetProductId' not found in active offerings.");
        }
        await Purchases.purchase(PurchaseParams.package(target));
      } else {
        await Purchases.purchase(PurchaseParams.package(pkg));
      }

      // Synchronize entitlements immediately on server
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('syncEntitlements');
        await callable.call();
      } catch (syncErr) {
        debugPrint("syncEntitlements call error: $syncErr");
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      final errorString = e.toString();
      bool isUserCancelled = errorString.contains('PURCHASE_CANCELLED') ||
          errorString.contains('Purchase was cancelled') ||
          errorString.contains('userCancelled: true');

      if (isUserCancelled) {
        debugPrint("ℹ️ Transaction cancelled by user.");
        if (mounted) {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
            content: Text("StoreKit Alert: ${e.toString()}"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Future<void> _restorePurchases() async {
    setState(() => isProcessing = true);
    try {
      await Purchases.restorePurchases();
      // Server-side entitlement sync
      final callable = FirebaseFunctions.instance.httpsCallable('syncEntitlements');
      await callable.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
            content: Text("Purchases restored successfully!"),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text("Restore failed: $e"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String billingPeriodText,
    String? introOfferText,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isPopular)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            ],
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
          if (introOfferText != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: Text(
                introOfferText,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
    // Dynamic Product Resolution from RevenueCat Offerings
    final creationPkg = _findPackage(
      isAnnualBilling
          ? 'axiom_creation_engine_yearly'
          : 'axiom_creation_engine_monthly',
    );
    final infinitePkg = _findPackage(
      isAnnualBilling
          ? 'axiom_infinite_brain_yearly'
          : 'axiom_infinite_brain_monthly',
    );

    // Dynamic price string with fallback
    final creationPrice = creationPkg?.storeProduct.priceString ??
        (isAnnualBilling ? "\$200.00/yr" : "\$19.99/mo");
    final creationBillingText = isAnnualBilling
        ? "billed annually"
        : "billed monthly";

    final infinitePrice = infinitePkg?.storeProduct.priceString ??
        (isAnnualBilling ? "\$450.00/yr" : "\$49.99/mo");
    final infiniteBillingText = isAnnualBilling
        ? "billed annually"
        : "billed monthly";

    // Introductory offer & Free trial inspection
    String? creationIntroText;
    final creationIntro = creationPkg?.storeProduct.introductoryPrice;
    if (creationIntro != null) {
      if (creationIntro.price == 0) {
        creationIntroText = "🎉 Free Trial Included";
      } else {
        creationIntroText = "Intro: ${creationIntro.priceString}";
      }
    }

    String? infiniteIntroText;
    final infiniteIntro = infinitePkg?.storeProduct.introductoryPrice;
    if (infiniteIntro != null) {
      if (infiniteIntro.price == 0) {
        infiniteIntroText = "🎉 Free Trial Included";
      } else {
        infiniteIntroText = "Intro: ${infiniteIntro.priceString}";
      }
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
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
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Elevate Your Mind",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              TextButton(
                onPressed: isProcessing ? null : _restorePurchases,
                child: const Text(
                  "Restore",
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Unlock Visual Lookbook and Cinematic Reels by upgrading to your Second Brain ecosystem tiers.",
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 20),

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
          const SizedBox(height: 20),

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
                    price: creationPrice,
                    billingPeriodText: creationBillingText,
                    introOfferText: creationIntroText,
                    color: const Color(0xFF3B82F6),
                    onTap: () => _executePurchase(
                      isAnnualBilling
                          ? 'axiom_creation_engine_yearly'
                          : 'axiom_creation_engine_monthly',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPricingCard(
                    title: "Infinite Brain",
                    price: infinitePrice,
                    billingPeriodText: infiniteBillingText,
                    introOfferText: infiniteIntroText,
                    color: const Color(0xFFA78BFA),
                    isPopular: true,
                    onTap: () => _executePurchase(
                      isAnnualBilling
                          ? 'axiom_infinite_brain_yearly'
                          : 'axiom_infinite_brain_monthly',
                    ),
                  ),
                  const SizedBox(height: 24),
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
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.business_center_outlined,
                            color: Colors.white54,
                            size: 28,
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Contact us for custom scaling and deployment.",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white38,
                            size: 14,
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
