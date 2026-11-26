import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'ledger.dart';

void main() => runApp(
  MaterialApp(
    title: 'SiteLedger',
    theme: ThemeData(colorSchemeSeed: const Color(0xff173d72)),
    home: const LedgerScreen(),
  ),
);

String money(int paise) =>
    '₹${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
String today() => DateTime.now().toIso8601String().substring(0, 10);
const roles = {
  'technician': 'Technician',
  'supervisor': 'Supervisor',
  'siteengineer': 'Site Engineer',
  'pm': 'Project Manager',
  'headoffice': 'Head Office',
};

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});
  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late final api = LedgerApi(
    Uri.parse(
      const String.fromEnvironment('API_URL', defaultValue: '') == ''
          ? 'http://${Platform.isAndroid ? '10.0.2.2' : '127.0.0.1'}:8000'
          : const String.fromEnvironment('API_URL'),
    ),
  );
  late Outbox box;
  static const demoPassword = 'local-demo-only';
  String role = 'technician',
      kind = 'Daily',
      message = '',
      password = demoPassword,
      filename = '',
      receipt = '';
  final days = TextEditingController(text: '1'),
      rate = TextEditingController(),
      expenseDate = TextEditingController(text: today()),
      description = TextEditingController();
  bool busy = false;
  List<Json> claims = [], pending = [];
  Json? comparison;
  String get owner => '${api.base}|$role';

  @override
  void dispose() {
    for (final field in [days, rate, expenseDate, description]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await task();
    } catch (e) {
      message = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() async {
    pending = await box.pending(owner);
    claims = List<Json>.from(await api.request('claims'));
    comparison = await api.request('comparison');
  }

  Future<void> login() async {
    final session = await api.request('login', {
      'account': role,
      'password': password,
    });
    box = await Outbox.open();
    api.token = session['token'];
    password = demoPassword;
    await refresh();
  }

  Future<void> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (result == null) return;
    final file = result.files.single;
    if (file.size > 2097152 || file.path == null) {
      throw Exception('Choose a file up to 2 MiB');
    }
    final bytes = await File(file.path!).readAsBytes();
    final header = latin1.decode(bytes.take(8).toList());
    if (!(header.startsWith('%PDF-') ||
        header.startsWith('\xff\xd8\xff') ||
        header.startsWith('\x89PNG\r\n\x1a\n'))) {
      throw Exception('Choose a PDF, JPEG or PNG receipt');
    }
    receipt = base64Encode(bytes);
    filename = file.name;
  }

  Future<void> save() async {
    final count = int.tryParse(days.text) ?? 0;
    final parts = rate.text.trim().split('.');
    if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(rate.text.trim())) {
      throw Exception('Enter a rate with up to two decimal places');
    }
    final paise =
        int.parse(parts.first) * 100 +
        (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
    final date = DateTime.tryParse(expenseDate.text);
    if (date == null ||
        date.toIso8601String().substring(0, 10) != expenseDate.text) {
      throw Exception('Enter a valid date (YYYY-MM-DD)');
    }
    if (count < 1 ||
        count > 366 ||
        paise < 1 ||
        paise > 100000000 ||
        description.text.trim().isEmpty ||
        receipt.isEmpty) {
      throw Exception(
        'Enter 1–366 days, a positive rate up to ₹1,000,000, particulars and a receipt',
      );
    }
    await box.save(owner, {
      'client_id': const Uuid().v4(),
      'project': project,
      'building': building,
      'kind': kind,
      'expense_date': expenseDate.text,
      'days': count,
      'rate_paise': paise,
      'description': description.text.trim(),
      'filename': filename,
      'receipt': receipt,
    });
    pending = await box.pending(owner);
    description.clear();
    rate.clear();
    receipt = '';
    filename = '';
    message = 'Saved on this device. Ready to sync.';
  }

  Widget field(String label, TextEditingController controller, {int? limit}) =>
      TextField(
        controller: controller,
        maxLength: limit,
        decoration: InputDecoration(labelText: label),
      );
  Widget button(String label, Future<void> Function() action) => FilledButton(
    onPressed: busy ? null : () => run(action),
    child: Text(label),
  );

  Future<void> decide(Json claim, String action) async {
    final body = <String, dynamic>{
      'version': claim['version'],
      'action': action,
    };
    if (action == 'Pay') {
      String reference = '', date = today();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Record payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: date,
                onChanged: (v) => date = v,
                decoration: const InputDecoration(
                  labelText: 'Payment date (YYYY-MM-DD)',
                ),
              ),
              TextField(
                onChanged: (v) => reference = v,
                decoration: const InputDecoration(
                  labelText: 'Payment reference',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Record payment'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      body.addAll({'reference': reference, 'payment_date': date});
    }
    await api.request("claims/${claim['id']}/decision", body);
    await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = api.token.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SiteLedger'),
        actions: [
          if (signedIn)
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      api.token = '';
                      claims = [];
                      pending = [];
                      comparison = null;
                      message = '';
                      receipt = '';
                      filename = '';
                      description.clear();
                      rate.clear();
                    }),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!signedIn) ...[
                const Text('Demo sign-in', style: TextStyle(fontSize: 24)),
                DropdownButton<String>(
                  value: role,
                  items: roles.entries
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.key,
                          child: Text(r.value),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => role = v!),
                ),
                TextFormField(
                  initialValue: demoPassword,
                  obscureText: true,
                  onChanged: (v) => password = v,
                  decoration: const InputDecoration(labelText: 'Demo password'),
                ),
                button('Sign in', login),
              ] else ...[
                Text(project, style: Theme.of(context).textTheme.headlineSmall),
                Text('$building · ${roles[role]}'),
                if (comparison != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Site overhead · actual cost'),
                    subtitle: Text(
                      'Quoted ${money(comparison!['quoted_paise'])} · ${comparison!['postings']} paid postings',
                    ),
                    trailing: Text(money(comparison!['actual_paise'])),
                  ),
                if (role == 'technician') ...[
                  const Divider(),
                  Text(
                    'New allowance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  DropdownButton<String>(
                    value: kind,
                    items: ['Daily', 'Food', 'Conveyance']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => kind = v!),
                  ),
                  field('Expense date (YYYY-MM-DD)', expenseDate),
                  field('Days', days),
                  field('Rate per day (₹)', rate),
                  field('Particulars', description, limit: 500),
                  TextButton(
                    onPressed: busy ? null : () => run(pick),
                    child: Text(
                      filename.isEmpty
                          ? 'Attach receipt (PDF or image)'
                          : filename,
                    ),
                  ),
                  button('Save to offline queue', save),
                  for (final p in pending)
                    ListTile(
                      title: Text(p['description']),
                      subtitle: Text("Waiting to sync · ${p['client_id']}"),
                    ),
                  if (pending.isNotEmpty)
                    button('Sync saved claims', () async {
                      await box.sync(
                        owner,
                        (data) => api.request('claims', data),
                      );
                      await refresh();
                    }),
                ],
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Claims',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: busy ? null : () => run(refresh),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (claims.isEmpty) const Text('No submitted claims.'),
                for (final c in claims)
                  ExpansionTile(
                    title: Text("${c['number']} · ${money(c['amount'])}"),
                    subtitle: Text(
                      [
                        c['status'],
                        roles[c['reviewer']],
                      ].whereType<String>().join(' · '),
                    ),
                    children: [
                      ListTile(
                        title: Text(c['description']),
                        subtitle: Text(
                          "${c['expense_date']} · ${c['kind']} · ${c['days']} × ${money(c['rate_paise'])}\n${c['filename']}",
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                final evidence = await api.request(
                                  "claims/${c['id']}/receipt",
                                );
                                await FilePicker.platform.saveFile(
                                  fileName:
                                      "${c['number']}-receipt.${c['filename'].toString().split('.').last.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}",
                                  bytes: base64Decode(evidence['receipt']),
                                );
                              }),
                        child: const Text('Save receipt'),
                      ),
                      if (c['payment'] != null)
                        ListTile(
                          title: Text("Paid ${c['payment']['paid_on']}"),
                          subtitle: Text(c['payment']['reference']),
                        ),
                      for (final e in c['history'])
                        ListTile(
                          dense: true,
                          title: Text("${roles[e['actor']]} · ${e['action']}"),
                          subtitle: Text("${e['at']} UTC"),
                        ),
                      if (c['reviewer'] == role)
                        Builder(
                          builder: (_) {
                            final action = {
                              'Submitted': 'Approve',
                              'Approved': 'Mark payable',
                              'Payable': 'Pay',
                            }[c['status']]!;
                            return button(action, () => decide(c, action));
                          },
                        ),
                    ],
                  ),
              ],
              if (busy) const LinearProgressIndicator(),
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
