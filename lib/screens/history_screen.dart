import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class CallHistoryItem {
  final String id;
  final String name;
  final String phone;
  final String status;
  final String duration;
  final String time;
  final String date;
  final String initials;
  final String? leadId;
  final String? agentName;
  final String? leadName;
  final String? clientEmail;
  final String? callTime;

  CallHistoryItem({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.duration,
    required this.time,
    required this.date,
    required this.initials,
    this.leadId,
    this.agentName,
    this.leadName,
    this.clientEmail,
    this.callTime,
  });

  factory CallHistoryItem.fromJson(Map<String, dynamic> json) {
    final clientName = json['client_name'] ?? json['name'] ?? 'Unknown Caller';

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

    return CallHistoryItem(
      id: json['id']?.toString() ?? '',
      name: clientName,
      phone: json['mobile'] ?? json['phone'] ?? '',
      status: json['call_status'] ?? json['status'] ?? 'accepted',
      duration: json['duration'] ?? '0:00',
      time: json['created_at'] ?? json['time'] ?? '',
      date: json['created_at'] ?? json['date'] ?? '',
      initials: initials,
      leadId: json['lead_id']?.toString(),
      agentName: json['agent_name'],
      leadName: json['lead_name'],
      clientEmail: json['client_email'],
      callTime: json['call_time'],
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  HistoryScreenState createState() => HistoryScreenState();
}

class HistoryScreenState extends State<HistoryScreen> {
  List<CallHistoryItem> _callHistory = [];
  List<CallHistoryItem> _filteredHistory = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _activeFilter = 'all';
  String _searchQuery = '';

  final Map<String, int> _stats = {'total': 0, 'accepted': 0, 'rejected': 0};

  @override
  void initState() {
    super.initState();
    _loadCallHistory();
  }

  Future<void> _loadCallHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.get('/call-history');
      if (response['data'] != null && response['data']['calls'] != null) {
        final calls = (response['data']['calls'] as List)
            .map((call) => CallHistoryItem.fromJson(call))
            .toList();
        setState(() {
          _callHistory = calls;
          _updateFilteredHistory();
          _updateStats();
        });
      } else {
        // Mock data for testing
        setState(() {
          _callHistory = [
            CallHistoryItem(
              id: '67266',
              name: 'Najwa Al Awadhi',
              phone: '+971508838828',
              status: 'accepted',
              duration: '2:45',
              time: 'Today, 9:52 PM',
              date: 'Today',
              initials: 'NA',
              leadId: '67266',
              agentName: 'EL',
              leadName: 'AR-RETAILS-FB-UAE-TE-EL-SEP',
              callTime: 'Today, 9:52 PM',
            ),
            CallHistoryItem(
              id: '67268',
              name: 'Sarah Johnson',
              phone: '+971509876543',
              status: 'rejected',
              duration: '-',
              time: 'Yesterday, 7:15 PM',
              date: 'Yesterday',
              initials: 'SJ',
              leadId: '67268',
              agentName: 'RK',
              leadName: 'US-TECH-LEAD-SJ',
              callTime: 'Yesterday, 7:15 PM',
            ),
            CallHistoryItem(
              id: '67269',
              name: 'Ahmed Hassan',
              phone: '+971501234567',
              status: 'accepted',
              duration: '1:23',
              time: 'Today, 12:53 PM',
              date: 'Today',
              initials: 'AH',
              leadId: '67269',
              agentName: 'MK',
              leadName: 'UAE-REAL-ESTATE-AH',
              callTime: 'Today, 12:53 PM',
            ),
            CallHistoryItem(
              id: '67271',
              name: 'Mohamed Ali',
              phone: '+971502345678',
              status: 'rejected',
              duration: '-',
              time: 'Yesterday, 3:45 PM',
              date: 'Yesterday',
              initials: 'MA',
              leadId: '67271',
              agentName: 'JD',
              leadName: 'SHARJAH-RETAIL-MA',
              callTime: 'Yesterday, 3:45 PM',
            ),
          ];
          _updateFilteredHistory();
          _updateStats();
        });
      }
    } catch (e) {
      Navigator.pushReplacementNamed(context, "/login");
      setState(() {
        _callHistory = [];
        _updateFilteredHistory();
        _updateStats();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateFilteredHistory() {
    List<CallHistoryItem> filtered = _callHistory;

    if (_activeFilter != 'all') {
      filtered = filtered
          .where((call) => call.status == _activeFilter)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (call) =>
                call.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                call.phone.contains(_searchQuery),
          )
          .toList();
    }

    setState(() {
      _filteredHistory = filtered;
    });
  }

  void _updateStats() {
    final total = _callHistory.length;
    final accepted = _callHistory
        .where((call) => call.status == 'accepted')
        .length;
    final rejected = _callHistory
        .where((call) => call.status == 'rejected')
        .length;

    setState(() {
      _stats['total'] = total;
      _stats['accepted'] = accepted;
      _stats['rejected'] = rejected;
    });
  }

  Future<void> _onRefresh() async {
    await _loadCallHistory();
  }

  void _showCallDetails(CallHistoryItem call) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Stack(
            children: [
              // Close button at top right
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ),
              // Dialog content
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ADE80),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Center(
                          child: Text(
                            call.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
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
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: call.status == 'accepted'
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                call.status == 'accepted'
                                    ? 'Accepted'
                                    : 'Rejected',
                                style: TextStyle(
                                  color: call.status == 'accepted'
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFDC2626),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Call Details',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow('Lead ID:', call.leadId ?? 'N/A'),
                  _buildDetailRow('Lead Name:', call.leadName ?? 'N/A'),
                  _buildDetailRow('Agent:', call.agentName ?? 'N/A'),
                  _buildDetailRow(
                    'Call Time:',
                    _formatCallTime(call.callTime ?? call.time),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

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
                      Image.asset(
                        'assets/images/justlogo.png',
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
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
                    Container(
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
                              : 'E',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Title
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Review your call activity',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Search Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _updateFilteredHistory();
                  });
                },
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search calls...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Filter Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildFilterTab('All', 'all'),
                  const SizedBox(width: 12),
                  _buildFilterTab('Accepted', 'accepted'),
                  const SizedBox(width: 12),
                  _buildFilterTab('Rejected', 'rejected'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Stats Cards
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildStatCard(
                    '${_stats['total']}',
                    'Total Calls',
                    const Color(0xFF4ADE80),
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    '${_stats['accepted']}',
                    'Accepted',
                    const Color(0xFF4ADE80),
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    '${_stats['rejected']}',
                    'Rejected',
                    const Color(0xFFEF4444),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Call History List
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
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
                              onPressed: _loadCallHistory,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4ADE80),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.call,
                              size: 64,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No calls found',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Your call history will appear here once you start receiving calls.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredHistory.length,
                          itemBuilder: (context, index) {
                            final call = _filteredHistory[index];
                            return _buildCallItem(call);
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

  Widget _buildFilterTab(String title, String value) {
    final isActive = _activeFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeFilter = value;
            _updateFilteredHistory();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF4ADE80)
                : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallItem(CallHistoryItem call) {
    return GestureDetector(
      onTap: () => _showCallDetails(call),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
                      if (call.phone.isNotEmpty)
                        Text(
                          call.phone,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: call.status == 'accepted'
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    call.status == 'accepted' ? 'Accepted' : 'Rejected',
                    style: TextStyle(
                      color: call.status == 'accepted'
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
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
                  _formatCallTime(call.callTime ?? call.time),
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              child: Row(
                children: [
                  Icon(Icons.menu, color: Colors.grey[400], size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Details',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

          return '${hour}:${minute.toString().padLeft(2, '0')} $period';
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
}
