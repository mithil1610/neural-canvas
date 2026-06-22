import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:neural_canvas/screens/auth_gate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../../utils/ui_utils.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isUploading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = _user?.displayName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateProfilePicture() async {
    if (_user == null) return;
    HapticFeedback.lightImpact();

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (image == null) return;

      setState(() {
        _isUploading = true;
      });

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/${_user.uid}/profile_pic/avatar.jpg');

      UploadTask uploadTask;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        uploadTask = storageRef.putData(bytes);
      } else {
        uploadTask = storageRef.putFile(File(image.path));
      }

      final snapshot = await uploadTask;
      final newUrl = await snapshot.ref.getDownloadURL();

      // Twin update action sequence
      // First: Run FirebaseAuth.instance.currentUser!.updatePhotoURL(newUrl)
      await _user.updatePhotoURL(newUrl);

      // Second: Save to database profile document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .set({
        'photoUrl': newUrl,
        'displayName': _nameController.text,
      }, SetOptions(merge: true));

      // Force a reload of the user object so local UI reflects changes
      await _user.reload();

      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Profile picture synchronized successfully!');
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Failed to update picture: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_user == null) return;
    HapticFeedback.lightImpact();

    setState(() {
      _isSaving = true;
    });

    try {
      await _user.updateDisplayName(_nameController.text);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .set({
        'displayName': _nameController.text,
      }, SetOptions(merge: true));

      await _user.reload();

      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Profile metadata synchronized successfully!');
      }
    } catch (e) {
      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Failed to update profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteStorageFolder(Reference ref) async {
    try {
      final listResult = await ref.listAll();
      for (var item in listResult.items) {
        await item.delete();
      }
      for (var prefix in listResult.prefixes) {
        await _deleteStorageFolder(prefix);
      }
    } catch (e) {
      if (kDebugMode) debugPrint("Storage delete folder error: $e");
    }
  }

  Future<void> _deleteAccount() async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account & Purge Vault'),
        content: const Text('This action is irreversible. All your data, uploads, and knowledge graphs will be permanently erased. Proceed?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Purge', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;

    setState(() {
      _isSaving = true;
    });

    try {
      // Step A: Storage
      await _deleteStorageFolder(FirebaseStorage.instance.ref().child('users/$uid'));

      // Step B: Firestore sub-collections
      final collections = ['knowledge_base', 'upcoming_events', 'chats'];
      for (var coll in collections) {
        try {
          final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).collection(coll).get();
          for (var doc in snapshot.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          if (kDebugMode) debugPrint("Firestore sub-collection $coll delete error: $e");
        }
      }

      // Step C: Remove user profile document
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      } catch (e) {
        if (kDebugMode) debugPrint("Firestore doc delete error: $e");
      }

      // Step D: Permanently delete auth credentials
      try {
        await user.delete();
      } catch (e) {
        if (kDebugMode) debugPrint("Auth deletion fallback triggered: $e");
        await FirebaseAuth.instance.signOut();
      }

    } catch (e) {
      if (mounted) {
        UIUtils.showFloatingSnackBar(context, 'Failed to purge account: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        Navigator.of(context).pushNamedAndRemoveUntil('/login_or_register', (route) => false);
      }
    }
  }

  Widget _buildUsageTracker() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final String accountTier = data['accountTier'] ?? 'free';
        final int aiUsageCount = data['aiUsageCount'] ?? 0;

        int limit = 15;
        if (accountTier == 'premium' || accountTier == 'pro') {
          limit = 750;
        } else if (accountTier == 'infinite') {
          limit = 3000;
        }

        double progress = aiUsageCount / limit;
        if (progress > 1.0) progress = 1.0;
        if (progress < 0.0) progress = 0.0;

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Neural Bandwidth Usage',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '$aiUsageCount / $limit frames used',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 6,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0EA5E9), Color(0xFFA78BFA)], // Electric Blue to Neural Purple
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Includes all automated scans, voice transcriptions, text logs, and chat context processing metrics.',
              style: TextStyle(fontSize: 10, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Configuration', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _user == null
          ? const Center(child: Text("Please login to configure your profile."))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Avatar Frame
                  GestureDetector(
                    onTap: _isUploading ? null : _updateProfilePicture,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          backgroundImage: _user.photoURL != null
                              ? CachedNetworkImageProvider(_user.photoURL!)
                              : null,
                          child: _user.photoURL == null && !_isUploading
                              ? Icon(Icons.person, size: 60, color: Theme.of(context).colorScheme.onSurfaceVariant)
                              : null,
                        ),
                        if (_isUploading)
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          ),
                        if (!_isUploading)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: 20,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Name Input
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Display Name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildUsageTracker(),
                  const SizedBox(height: 40),
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Save Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () async {
                      HapticFeedback.lightImpact();
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const AuthGate()),
                          (Route<dynamic> route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: const Text('Sign Out / Log Out', style: TextStyle(color: Colors.redAccent)),
                  ),
                  const SizedBox(height: 32),
                  TextButton(
                    onPressed: _isSaving ? null : _deleteAccount,
                    child: const Text(
                      'Delete Account & Purge Vault',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
