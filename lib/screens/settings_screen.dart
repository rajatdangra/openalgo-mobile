import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/api_config.dart';
import '../models/index_config.dart';
import '../services/openalgo_api_service.dart';
import '../services/storage_service.dart';
import '../utils/app_theme.dart';
import 'login_screen.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'api_status_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ApiConfig config;

  const SettingsScreen({super.key, required this.config});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final OpenAlgoApiService _apiService;
  final _storageService = StorageService();
  
  bool _isLoading = false;
  Map<String, dynamic>? _funds;
  String? _brokerName;
  bool _isAnalyzeMode = false;
  bool _isLoadingAnalyzerStatus = false;
  List<String> _selectedIndices = [];

  @override
  void initState() {
    super.initState();
    _apiService = OpenAlgoApiService(widget.config);
    _loadSelectedIndices();
    _fetchFunds();
    _fetchBrokerInfo();
    _fetchAnalyzerStatus();
  }

  Future<void> _loadSelectedIndices() async {
    final indices = await _storageService.getSelectedIndices();
    if (mounted) {
      setState(() {
        _selectedIndices = indices;
      });
    }
  }

  // Helper method to safely parse dynamic values to double
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Future<void> _updateSelectedIndices(List<String> indices) async {
    await _storageService.saveSelectedIndices(indices);
    setState(() {
      _selectedIndices = indices;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Index configuration updated. Refresh to see changes.'),
        backgroundColor: AppTheme.profitGreen,
      ),
    );
  }

  Future<void> _fetchBrokerInfo() async {
    try {
      final pingData = await _apiService.ping();
      if (mounted) {
        setState(() {
          // Support both 'broker' and 'broker_name' field names
          final data = pingData['data'] as Map<String, dynamic>;
          final brokerNameValue = data['broker'] ?? data['broker_name'];
          _brokerName = brokerNameValue?.toString() ?? 'Unknown';
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching broker info: $e');
      }
    }
  }

  Future<void> _fetchAnalyzerStatus() async {
    setState(() => _isLoadingAnalyzerStatus = true);

    bool parseMode(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'on' || s == 'analyze' || s == 'analyzer' || s == 'live';
    }

    try {
      final status = await _apiService.getAnalyzerStatus();
      if (!mounted) return;

      final data = status['data'] as Map<String, dynamic>? ?? {};
      final dynamic modeRaw = data['analyze_mode'] ?? data['mode'] ?? data['analyzermode'];
      final bool mode = parseMode(modeRaw);

      setState(() {
        _isAnalyzeMode = mode;
        _isLoadingAnalyzerStatus = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingAnalyzerStatus = false);
      if (kDebugMode) debugPrint('Error fetching analyzer status: $e');
      if (mounted) setState(() => _isAnalyzeMode = false);
    }
  }

  Future<void> _toggleAnalyzerMode(bool value) async {
    setState(() => _isLoadingAnalyzerStatus = true);
    try {
      await _apiService.toggleAnalyzer(value);
      if (mounted) {
        setState(() {
          _isAnalyzeMode = value;
          _isLoadingAnalyzerStatus = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Switched to Analyze Mode' : 'Switched to Live Mode'),
            backgroundColor: value ? AppTheme.warningOrange : AppTheme.profitGreen,
          ),
        );

        // Refresh account funds automatically after toggling mode
        _fetchFunds();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAnalyzerStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle mode: $e'),
            backgroundColor: AppTheme.lossRed,
          ),
        );
      }
    }
  }

  Future<void> _fetchFunds() async {
    setState(() => _isLoading = true);
    try {
      final funds = await _apiService.getFunds();
      if (mounted) {
        setState(() {
          _funds = funds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      if (kDebugMode) {
        debugPrint('Error fetching funds: $e');
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.clearApiConfig();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchAnalyzerStatus();
                await _fetchFunds();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Index Configuration Section
                  _buildIndexConfigSection(),
                  
                  const SizedBox(height: 24),
                  
                  // Analyzer Mode Section
                  _buildAnalyzerModeSection(),
                  
                  const SizedBox(height: 24),
                  
                  // Funds Section
                  if (_funds != null) _buildFundsSection(),
                  
                  if (_funds != null) const SizedBox(height: 24),
                  
                  // Connection Info Section
                  _buildConnectionSection(),
                  
                  const SizedBox(height: 24),
                  
                  // About Section
                  _buildAboutSection(),
                ],
              ),
            ),
    );
  }



  Widget _buildFundsSection() {
    // Safely convert API values to double (handles both String and num types)
    final availableCash = _parseDouble(_funds!['availablecash']);
    final usedMargin = _parseDouble(_funds!['utiliseddebits']);
    final m2mRealized = _parseDouble(_funds!['m2mrealized']);
    final m2mUnrealized = _parseDouble(_funds!['m2munrealized']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  color: AppTheme.profitGreen,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Account Funds',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFundItem('Available Cash', availableCash, AppTheme.profitGreen),
            const SizedBox(height: 8),
            _buildFundItem('Used Margin', usedMargin, AppTheme.textSecondary),
            const SizedBox(height: 8),
            _buildFundItem('M2M Realized', m2mRealized, AppTheme.getPnlColor(m2mRealized)),
            const SizedBox(height: 8),
            _buildFundItem('M2M Unrealized', m2mUnrealized, AppTheme.getPnlColor(m2mUnrealized)),
          ],
        ),
      ),
    );
  }

  Widget _buildFundItem(String label, double value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildConnectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.link,
                  color: AppTheme.accentBlue,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Connection',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontTheme.bold,
(