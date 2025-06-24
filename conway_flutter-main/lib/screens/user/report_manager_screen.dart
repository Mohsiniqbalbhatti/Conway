import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../constants/colors.dart';
import '../../constants/api_config.dart';
import '../../helpers/database_helper.dart';
import 'report_detail_screen.dart';

class ReportManagerScreen extends StatefulWidget {
  const ReportManagerScreen({Key? key}) : super(key: key);

  @override
  State<ReportManagerScreen> createState() => _ReportManagerScreenState();
}

class _ReportManagerScreenState extends State<ReportManagerScreen> {
  List<dynamic> _reports = [];
  bool _loading = true;
  String? _error;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _checkAdminAndFetchReports();
  }

  Future<void> _checkAdminAndFetchReports() async {
    final user = await DBHelper().getUser();
    setState(() {
      _currentUserEmail = user?.email;
    });
    if (_currentUserEmail != 'mohsiniqbalbhatti0024@gmail.com') {
      setState(() {
        _loading = false;
        _error = 'Access denied. You are not an admin.';
      });
      return;
    }
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/reports'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _reports = data['reports'] ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to fetch reports.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  void _showReportDetail(Map<String, dynamic> report) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportDetailScreen(report: report),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Reports'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.lightGrey,
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
              : _reports.isEmpty
              ? const Center(child: Text('No reports found.'))
              : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _reports.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final report = _reports[index];
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    child: ListTile(
                      title: Text('Report ID: ${report['_id']}'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reporter: ${report['reporterEmail']}'),
                          Text('Reported: ${report['reportedUserEmail']}'),
                          Text('Created: ${report['createdAt'] ?? ''}'),
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                      onTap: () => _showReportDetail(report),
                    ),
                  );
                },
              ),
    );
  }
}
