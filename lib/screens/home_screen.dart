import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/fcm_service.dart';

class CallRequest {
  final String id;
  final String name;
  final String phone;
  final String initials;
  final String type;
  final String purpose;
  final String timeAgo;
  final String originalTime; // Store original time for formatting
  final String status;
  final int timestamp;
  final String? leadId;
  final String? callId;
  final String? agentName;
  final String? leadName;
  final String? clientEmail;

  CallRequest({
    required this.id,
    required this.name,
    required this.phone,
    required this.initials,
    required this.type,
    required this.purpose,
    required this.timeAgo,
    required this.originalTime,
    required this.status,
    required this.timestamp,
    this.leadId,
    this.callId,
    this.agentName,
    this.leadName,
    this.clientEmail,
  });

  factory CallRequest.fromJson(Map<String, dynamic> json) {
    final clientName = json['client_name'] ?? 'Unknown Caller';
    final mobile = json['mobile'] ?? '';
    final createdAt = json['created_at'] ?? '';

    // Safe initials generation
    String initials = 'UN';
    if (clientName.isNotEmpty && clientName != 'Unknown Caller') {
      try {
        final nameParts = clientName.trim().split(' ');
        if (nameParts.length >= 2) {
          initials = '${nameParts[0][0]}${nameParts[1][0]}'.toUpperCase();
        } else if (nameParts.length == 1 && nameParts[0].length >= 2) {
          initials = nameParts[0].substring(0, 2).toUpperCase();
        } else if (nameParts.length == 1 && nameParts[0].length == 1) {
          initials = '${nameParts[0][0]}U'.toUpperCase();
        }
      } catch (e) {
        initials = 'UN';
      }
    }

    return CallRequest(
      id: '${json['lead_id']}_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().millisecondsSinceEpoch % 1000).toString().padLeft(3, '0')}',
      name: clientName,
      phone: mobile,
      initials: initials,
      type: 'Call',
      purpose: 'Incoming call',
      timeAgo: _formatTimeAgo(createdAt),
      originalTime: createdAt, // Store original time
      status: json['call_status'] ?? 'pending',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      leadId: json['lead_id']?.toString(),
      callId: json['call_id']?.toString(),
      agentName: json['agent_name'],
      leadName: json['lead_name'],
      clientEmail: json['client_email'],
    );
  }

  static String _formatTimeAgo(String createdAt) {
    try {
      final createdDate = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(createdDate);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return 'Just now';
    }
  }
}

class CallStats {
  final int pendingCalls;
  final int totalCalls;
  final int acceptedCalls;
  final int rejectedCalls;

  CallStats({
    required this.pendingCalls,
    required this.totalCalls,
    required this.acceptedCalls,
    required this.rejectedCalls,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> 
    with WidgetsBindingObserver {
  List<CallRequest> _callRequests = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _processingCallId;
  String? _processingAction; // 'accept' or 'reject'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupFCMHandler();
    // Clear all notifications when app opens
    _clearNotifications();
    // Delay the API call slightly to ensure the widget is fully mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPendingCalls();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Clear notifications and refresh data when app comes to foreground
    if (state == AppLifecycleState.resumed && mounted) {
      _clearNotifications(); // Clear notifications when app resumes
      _loadPendingCalls();
    }
    // Also clear notifications when app becomes inactive (iOS) or paused (Android) 
    // and then becomes active again
    if (state == AppLifecycleState.inactive && mounted) {
      _clearNotifications(); // Clear notifications when app becomes active
    }
  }

  /// Clear all notifications when the user opens the app
  Future<void> _clearNotifications() async {
    try {
      await FCMService().clearAllNotifications();
    } catch (e) {
      // Silently handle any errors in clearing notifications
    }
  }

  void _setupFCMHandler() {
    // Set up FCM notification handler for real-time call updates
    FCMService().initialize(onNotificationReceived: _handleFCMNotification);
  }

  void _handleFCMNotification(Map<String, dynamic> data) {
    // FCM Call notification received
    // Check if this is a call notification
    if (data.containsKey('call_id') || data.containsKey('lead_id')) {
      // Refresh the call list to get real-time updates
      if (mounted) {
        _loadPendingCalls();
      }
    }
  }

  Future<void> _loadPendingCalls() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if user is logged in first
      final userData = await ApiService.getUserData();
      if (userData == null) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
        return;
      }
      
      // Add a small delay for iOS compatibility
      await Future.delayed(const Duration(milliseconds: 100));
      
      final response = await ApiService.get('/getPendingCalls');
      
      if (!mounted) return;
      
      if (response['data'] != null &&
          response['data']['pending_calls'] != null) {
        final calls = (response['data']['pending_calls'] as List)
            .map((call) => CallRequest.fromJson(call))
            .where(
              (call) => call.status == 'pending',
            ) // Only show pending calls
            .toList();
        
        setState(() {
          _callRequests = calls;
        });
      } else {
        setState(() {
          _callRequests = [];
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      _handleSessionError(errorMessage);
      
      setState(() {
        _errorMessage = errorMessage;
      });
      
      // Retry after 2 seconds if it's a network error and not a session error
      if (!errorMessage.contains('Session') && mounted) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _loadPendingCalls();
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatCallTime(String timeString) {
    try {
      // Handle "Today, 9:52 PM" format
      if (timeString.contains('Today')) {
        return timeString;
      }

      // Handle "Yesterday, 7:15 PM" format
      if (timeString.contains('Yesterday')) {
        return timeString;
      }

      // Handle format like "2025-09-18 00 53:10" - extract just the time part
      if (timeString.contains('-') && timeString.contains(' ')) {
        try {
          // Split by space and take the time part (after the date)
          final parts = timeString.split(' ');
          if (parts.length >= 2) {
            final timePart = parts[1];
            // Handle format like "00 53:10" -> "00:53:10"
            final correctedTime = timePart.replaceAll(' ', ':');
            // Parse the time
            final timeComponents = correctedTime.split(':');
            if (timeComponents.length >= 2) {
              int hour = int.tryParse(timeComponents[0]) ?? 0;
              int minute = int.tryParse(timeComponents[1]) ?? 0;

              // Convert to 12-hour format
              String period = hour >= 12 ? 'PM' : 'AM';
              hour = hour % 12;
              if (hour == 0) hour = 12;

              return '$hour:${minute.toString().padLeft(2, '0')} $period';
            }
          }
        } catch (e) {
          // If parsing fails, continue to next format
        }
      }

      // Handle UTC format like "2025-09-17T20:55:37.0000000Z"
      if (timeString.contains('T') && timeString.contains('Z')) {
        try {
          // Parse UTC time
          DateTime utcTime = DateTime.parse(timeString);

          // Convert to local time
          DateTime localTime = utcTime.toLocal();

          // Format as readable time (12-hour format with AM/PM)
          int hour = localTime.hour;
          int minute = localTime.minute;
          String period = hour >= 12 ? 'PM' : 'AM';

          // Convert to 12-hour format
          hour = hour % 12;
          if (hour == 0) hour = 12;

          return '$hour:${minute.toString().padLeft(2, '0')} $period';
        } catch (e) {
          // If parsing fails, return original string
          return timeString;
        }
      }

      // For other formats, return as is
      return timeString;
    } catch (e) {
      return timeString;
    }
  }

  void _handleSessionError(String errorMessage) {
    // Check if it's a session-related error
    if (errorMessage.contains('Session has been ended') || 
        errorMessage.contains('Session expired')) {
      // Show message and redirect to login
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Navigate to login after a short delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed('/login');
          }
        });
      }
    }
  }

  Future<void> _handleCallAction(String callId, String action) async {
    setState(() {
      _processingCallId = callId;
      _processingAction = action;
    });

    try {
      // Find the call request to get the lead_id and call_id
      final callRequest = _callRequests.firstWhere(
        (call) => call.id == callId,
        orElse: () => throw Exception('Call request not found'),
      );

      final leadId = callRequest.leadId ?? callId.split('_')[0];
      final apiCallId = callRequest.callId ?? callId;

      // Prepare API status: 1 for accept, 0 for decline
      final apiStatus = action == 'accept' ? 1 : 0;

      await ApiService.post(
        '/accept-call-notification',
        body: {
          'lead_id': int.parse(leadId),
          'call_id': apiCallId,
          'status': apiStatus,
        },
      );

      // Update local state
      setState(() {
        final index = _callRequests.indexWhere((call) => call.id == callId);
        if (index != -1) {
          _callRequests[index] = CallRequest(
            id: _callRequests[index].id,
            name: _callRequests[index].name,
            phone: _callRequests[index].phone,
            initials: _callRequests[index].initials,
            type: _callRequests[index].type,
            purpose: _callRequests[index].purpose,
            timeAgo: _callRequests[index].timeAgo,
            originalTime: _callRequests[index].originalTime,
            status: action == 'accept' ? 'accepted' : 'rejected',
            timestamp: _callRequests[index].timestamp,
            leadId: _callRequests[index].leadId,
            callId: _callRequests[index].callId,
            agentName: _callRequests[index].agentName,
            leadName: _callRequests[index].leadName,
            clientEmail: _callRequests[index].clientEmail,
          );
        }
      });

      if (action == 'accept') {
        // Launch phone call immediately when accepting
        if (callRequest.phone.isNotEmpty) {
          await _launchPhoneCall(callRequest.phone);
        }
        await _showSuccessModal(callRequest.name, callRequest.phone);
      } else {
        await _showDeclineModal(callRequest.name);
      }

      // Remove the call from pending list after showing modal
      setState(() {
        _callRequests.removeWhere((call) => call.id == callId);
      });
    } catch (e) {
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      _handleSessionError(errorMessage);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to $action call: $errorMessage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _processingCallId = null;
        _processingAction = null;
      });
    }
  }

  Future<void> _showSuccessModal(String callerName, String phoneNumber) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF4ADE80),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 24),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.call, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Call Accepted!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Connecting call with $callerName...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Call has been connected successfully!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: index == 1 ? 1.0 : 0.5,
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeclineModal(String callerName) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 24),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.call_end,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Call Declined',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Call from $callerName was declined',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Call has been declined and removed from queue.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _launchPhoneCall(String phoneNumber) async {
    try {
      // Clean the phone number (remove any non-digit characters except +)
      String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      // Ensure it starts with + if it's an international number
      if (!cleanNumber.startsWith('+') && cleanNumber.length > 10) {
        cleanNumber = '+$cleanNumber';
      }

      final Uri phoneUri = Uri(scheme: 'tel', path: cleanNumber);

      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(
          phoneUri, 
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank'
        );
      } else {
        // Fallback: try with a different approach
        final String dialString = 'tel:$cleanNumber';
        final Uri fallbackUri = Uri.parse(dialString);
        await launchUrl(
          fallbackUri, 
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank'
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to launch phone dialer.\nPhone: $phoneNumber'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Copy',
              textColor: Colors.white,
              onPressed: () {
                // Copy phone number to clipboard
                try {
                  Clipboard.setData(ClipboardData(text: phoneNumber));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Phone number copied to clipboard'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  // Handle clipboard error silently
                }
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    FCMService().getFCMToken();
    return Scaffold(
      backgroundColor: const Color(0xFF0D3333),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.asset(
                          'assets/images/justlogo.png',
                          fit: BoxFit.contain,
                          width: 24,
                          height: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'SkyLead',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (user != null)
                    GestureDetector(
                      onTap: () {
                        // Navigate to profile
                        Navigator.of(context).pushNamed('/profile');
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            user.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Title Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Manage incoming call requests',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Pending Calls Count Card
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    '${_callRequests.length}',
                    style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Pending Calls',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Connection Status
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4ADE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Connected',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: const Text(
                'Pending Calls',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Calls List
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: RefreshIndicator(
                  onRefresh: _loadPendingCalls,
                  color: const Color(0xFF4ADE80),
                  child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF4ADE80),
                          ),
                        ),
                      )
                    : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadPendingCalls,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _callRequests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.call,
                              size: 64,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.7,
                              child: const Text(
                                'No pending calls',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.7,
                              child: const Text(
                                'All caught up! New call requests will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _callRequests.length,
                        itemBuilder: (context, index) {
                          final call = _callRequests[index];
                          return _buildCallCard(call);
                        },
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallCard(CallRequest call) {
    final isProcessingAccept =
        _processingCallId == call.id && _processingAction == 'accept';
    final isProcessingReject =
        _processingCallId == call.id && _processingAction == 'reject';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF4ADE80),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Center(
                  child: Text(
                    call.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.name,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // if (call.phone.isNotEmpty)
                    //   Text(
                    //     call.phone,
                    //     style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    //   ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Pending',
                  style: TextStyle(
                    color: Color(0xFFD97706),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (call.leadId != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Lead ID: ${call.leadId}',
                    style: const TextStyle(
                      color: Color(0xFF0369A1),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                _formatCallTime(call.originalTime),
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isProcessingAccept || isProcessingReject
                      ? null
                      : () => _handleCallAction(call.id, 'accept'),
                  icon: isProcessingAccept
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.call, size: 18),
                  label: Text(
                    isProcessingAccept ? 'Processing...' : 'Accept & Call',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4ADE80),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isProcessingAccept || isProcessingReject
                      ? null
                      : () => _handleCallAction(call.id, 'reject'),
                  icon: isProcessingReject
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.call_end, size: 18),
                  label: Text(isProcessingReject ? 'Processing...' : 'Decline'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
