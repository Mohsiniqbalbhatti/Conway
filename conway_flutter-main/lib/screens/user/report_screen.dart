import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../constants/colors.dart';
import 'package:http/http.dart' as http;
import '../../constants/api_config.dart';
import '../../helpers/database_helper.dart';

class ReportScreen extends StatefulWidget {
  final String? reportedUserEmail;
  final String? message;

  const ReportScreen({Key? key, this.reportedUserEmail, this.message})
    : super(key: key);

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  File? _screenshot;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.reportedUserEmail != null) {
      _emailController.text = widget.reportedUserEmail!;
    }
  }

  Future<void> _pickScreenshot() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _screenshot = File(picked.path);
      });
    }
  }

  void _submitReport() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/report');
      final request = http.MultipartRequest('POST', uri);
      final reporterEmail = await _getCurrentUserEmail();
      request.fields['reporterEmail'] = reporterEmail ?? '';
      request.fields['reportedUserEmail'] = _emailController.text.trim();
      request.fields['reportedMessage'] = widget.message ?? '';
      request.fields['description'] = _descriptionController.text.trim();
      if (_screenshot != null) {
        request.files.add(
          await http.MultipartFile.fromPath('screenshot', _screenshot!.path),
        );
      }
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      setState(() => _submitting = false);
      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted successfully!')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        final errorMsg =
            response.body.isNotEmpty
                ? response.body
                : 'Failed to submit report.';
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $errorMsg')));
        }
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error submitting report: $e')));
      }
    }
  }

  Future<String?> _getCurrentUserEmail() async {
    // Try to get the current user's email from local DB if available
    // If not, fallback to empty string (user must enter manually)
    try {
      // Import DBHelper and User if not already
      // import '../../helpers/database_helper.dart';
      // import '../../models/user.dart';
      final dbHelper = await DBHelper().getUser();
      return dbHelper?.email;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Message'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: AppColors.lightGrey,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Reported User Email',
                  labelStyle: TextStyle(color: AppColors.secondaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primaryColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.primaryColor,
                      width: 2,
                    ),
                  ),
                  fillColor: Colors.white,
                  filled: true,
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: AppColors.textColor),
              ),
              const SizedBox(height: 18),
              if (widget.message != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.message,
                        color: AppColors.secondaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reported Message: "${widget.message}"',
                          style: TextStyle(
                            color: AppColors.textColor,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.message != null) const SizedBox(height: 18),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Describe the issue',
                  labelStyle: TextStyle(color: AppColors.secondaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primaryColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: AppColors.primaryColor,
                      width: 2,
                    ),
                  ),
                  fillColor: Colors.white,
                  filled: true,
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                maxLines: 4,
                style: TextStyle(color: AppColors.textColor),
              ),
              const SizedBox(height: 18),
              Text(
                'Attach Screenshot (optional):',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryColor,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _pickScreenshot,
                    icon: const Icon(Icons.image),
                    label: const Text('Pick Image'),
                  ),
                  const SizedBox(width: 14),
                  if (_screenshot != null)
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_screenshot!, height: 80),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _submitting ? null : _submitReport,
                  child:
                      _submitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                            'Submit Report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
