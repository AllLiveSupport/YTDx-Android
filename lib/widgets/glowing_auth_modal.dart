import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class GlowingAuthModal extends StatefulWidget {
  final Function() onLoggedIn;

  const GlowingAuthModal({super.key, required this.onLoggedIn});

  @override
  State<GlowingAuthModal> createState() => _GlowingAuthModalState();
}

class _GlowingAuthModalState extends State<GlowingAuthModal> {
  String userCode = 'ABCD-1234';
  String verifyUrl = 'https://www.google.com/device';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCode();
  }

  Future<void> _fetchCode() async {
    final data = await AuthService.initiateDeviceAuth();
    if (mounted) {
      setState(() {
        userCode = data['user_code'] ?? 'ABCD-1234';
        verifyUrl = data['verification_url'] ?? 'https://www.google.com/device';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF131418),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF282B34), width: 1),
      ),
      child: Container(
        width: 460,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        decoration: BoxDecoration(
          color: const Color(0xFF131418),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.cyan.withValues(alpha: 0.12),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            const Text(
              'DEVICE AUTHENTICATION',
              style: TextStyle(
                fontSize: 16,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w300,
                color: Color(0xFFE5E7EB),
                fontFamily: 'serif',
              ),
            ),
            const SizedBox(height: 28),

            // Glowing Device Code Box
            if (isLoading)
              const CircularProgressIndicator(color: AppColors.glowCyan)
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1C22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2C303B)),
                ),
                child: Text(
                  userCode,
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 6,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: Color(0xFFE0F2FE),
                        blurRadius: 15,
                      ),
                      Shadow(
                        color: Color(0xFF38BDF8),
                        blurRadius: 25,
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // Instruction Subtitle
            const Text(
              'Enter this code on your other device to log in securely.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF9CA3AF),
                height: 1.4,
              ),
            ),

            const SizedBox(height: 26),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                  label: const Text('Copy Code', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF374151)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: userCode));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied to clipboard!'), duration: Duration(seconds: 2)),
                    );
                  },
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16, color: Colors.white),
                  label: const Text('Open google.com/device', style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(verifyUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
