import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class UserProfileScreen extends StatelessWidget {
  final String userName;
  final String userEmail;
  final String? profileUrl;

  const UserProfileScreen({
    super.key,
    required this.userName,
    required this.userEmail,
    this.profileUrl,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasProfileUrl = profileUrl != null && profileUrl!.isNotEmpty;
    final Color primaryColor = const Color(0xFF19BFB7); // Consistent color

    return Scaffold(
      appBar: AppBar(
        title: Text(userName, style: const TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 80,
                backgroundColor: Colors.grey[300],
                backgroundImage:
                    hasProfileUrl
                        ? CachedNetworkImageProvider(profileUrl!)
                        : null,
                child:
                    !hasProfileUrl
                        ? Icon(Icons.person, size: 80, color: Colors.grey[600])
                        : null,
              ),
              const SizedBox(height: 24),
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                userEmail,
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
