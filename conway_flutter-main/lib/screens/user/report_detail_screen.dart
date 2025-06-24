import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../constants/colors.dart';
import '../../constants/api_config.dart';
import '../../helpers/database_helper.dart';

class ReportDetailScreen extends StatefulWidget {
  final Map<String, dynamic> report;
  const ReportDetailScreen({Key? key, required this.report}) : super(key: key);

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final TextEditingController _wordsController = TextEditingController();
  bool _submitting = false;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _getCurrentUserEmail();
  }

  Future<void> _getCurrentUserEmail() async {
    final user = await DBHelper().getUser();
    setState(() {
      _currentUserEmail = user?.email;
    });
  }

  Future<void> _addWordsToProfanityList() async {
    final words = _wordsController.text.trim();
    if (words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter word(s) to add.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/profanity/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'words': words, 'adminEmail': _currentUserEmail}),
      );
      setState(() => _submitting = false);
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Words added to custom profanity list!'),
          ),
        );
        _wordsController.clear();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${response.body}')));
      }
    } catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserEmail != 'mohsiniqbalbhatti0024@gmail.com') {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Report Details'),
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Access denied. You are not an admin.')),
      );
    }
    final report = widget.report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Details'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.lightGrey,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            Text(
              'Report ID: ${report['_id']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Reporter: ${report['reporterEmail']}'),
            Text('Reported User: ${report['reportedUserEmail']}'),
            if (report['reportedMessage'] != null &&
                report['reportedMessage'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Reported Message: ${report['reportedMessage']}'),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('Description: ${report['description']}'),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('Created At: ${report['createdAt']}'),
            ),
            if (report['screenshotUrl'] != null &&
                report['screenshotUrl'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Image.network(
                  report['screenshotUrl'],
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Add word(s) to custom profanity list:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _wordsController,
              decoration: const InputDecoration(
                hintText:
                    'Enter word or comma-separated words (e.g. bad,word,add)',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _submitting ? null : _addWordsToProfanityList,
                child:
                    _submitting
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                          'Add to Profanity List',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
