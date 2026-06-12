import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';

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

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isUploading = true;
      });

      final file = result.files.first;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/${_user.uid}/profile_pic/avatar.jpg');

      UploadTask uploadTask;
      if (kIsWeb) {
        uploadTask = storageRef.putData(file.bytes!);
      } else {
        uploadTask = storageRef.putFile(File(file.path!));
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture synchronized successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update picture: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile metadata synchronized successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
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
                ],
              ),
            ),
    );
  }
}
