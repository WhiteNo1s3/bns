import 'dart:io' show File, Platform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bns/core/keybinds.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/import/bns_importer.dart';

/// Modern desktop shell for PC (Windows/macOS/Linux primary use).
///
/// - Clean modern sidebar menu using NavigationRail (feels like a proper modern app).
/// - Selected destination clearly marked with teal accent + background (same relaxing palette).
/// - Generous but clean spacing, keyboard-friendly.
/// - Keeps the exact same coloring scheme (teal/sage relaxing tones + green brain).
/// - PC is more robust: bigger click areas, clear selection, sidebar always visible on wide screens.
/// - Mobile / narrow keeps the simple flow (no sidebar).
///
/// All screens remain fully compatible with the same .bns format.
/// Extra PC robust data (keybinds etc.) travels inside the .bns.
class BnsDesktopShell extends StatefulWidget {
  final Widget child;
  final String currentPath;

  const BnsDesktopShell({
    super.key,
    required this.child,
    required this.currentPath,
  });

  @override
  State<BnsDesktopShell> createState() => _BnsDesktopShellState();
}

class _BnsDesktopShellState extends State<BnsDesktopShell> {
  int _selectedIndex = 0;

  final List<_DesktopDestination> _destinations = const [
    _DesktopDestination(
      icon: Icons.today_outlined,
      selectedIcon: Icons.today,
      label: 'Today',
      route: '/',
      tooltip: 'Today\'s gentle steps + diary  •  Ctrl+T',
    ),
    _DesktopDestination(
      icon: Icons.list_alt_outlined,
      selectedIcon: Icons.list_alt,
      label: 'Routines',
      route: '/routines',
      tooltip: 'Manage all routines  •  Ctrl+R',
    ),
    _DesktopDestination(
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Calendar',
      route: '/calendar',
      tooltip: 'Calendar + day view',
    ),
    _DesktopDestination(
      icon: Icons.psychology_outlined,
      selectedIcon: Icons.psychology,
      label: 'Memories',
      route: '/memories',
      tooltip: 'Memory garden, search, warnings  •  Ctrl+M',
    ),
    _DesktopDestination(
      icon: Icons.mic_outlined,
      selectedIcon: Icons.mic,
      label: 'Capture',
      route: '/capture',
      tooltip: 'Quick voice or text capture  •  Ctrl+N',
    ),
    _DesktopDestination(
      icon: Icons.sync_alt_outlined,
      selectedIcon: Icons.sync_alt,
      label: 'Sync & PC',
      route: '/sync',
      tooltip: 'LAN sync + PC keybinds + settings  •  Ctrl+,',
    ),
  ];

  @override
  void didUpdateWidget(covariant BnsDesktopShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateSelectedFromPath();
  }

  @override
  void initState() {
    super.initState();
    _updateSelectedFromPath();
  }

  void _updateSelectedFromPath() {
    final path = widget.currentPath;
    int index = _destinations.indexWhere((d) => d.route == path);
    if (index == -1) {
      // Fallbacks
      if (path.startsWith('/routines'))
        index = 1;
      else if (path.startsWith('/calendar'))
        index = 2;
      else if (path.startsWith('/memories'))
        index = 3;
      else if (path.startsWith('/capture'))
        index = 4;
      else if (path.startsWith('/sync'))
        index = 5;
      else
        index = 0;
    }
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
    }
  }

  void _onDestinationSelected(int index) {
    final dest = _destinations[index];
    setState(() => _selectedIndex = index);
    context.go(dest.route);
  }

  // --- Menu bar actions (File / View / Help — discoverable, power-user natural) ---

  static const Map<String, String> _routeToKeybindId = {
    '/': 'open_today',
    '/routines': 'open_routines',
    '/calendar': 'open_calendar',
    '/memories': 'open_memories',
    '/capture': 'quick_capture',
    '/sync': 'open_sync',
  };

  Future<void> _exportBackup() async {
    try {
      final f = await BnsExporter.exportFullSnapshot();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Backup saved: ${f.path.split(Platform.pathSeparator).last}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export had a problem: $e')));
    }
  }

  Future<void> _importBackup() async {
    final res = await FilePicker.platform.pickFiles();
    final path = res?.files.single.path;
    if (path == null) return;
    try {
      await BnsImporter.importMerge(File(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Backup merged in. Thank you for keeping things together.')));
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import had a problem: $e')));
    }
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('BNS 0.12a'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Gentle, privacy-first support for routines, memory and feeling good about the progress you make.'),
            SizedBox(height: 12),
            Text('Your data lives on your devices — nowhere else, no cloud, '
                'no accounts. Devices share directly over your own Wi-Fi, and '
                '.bns files are your portable backup for moving by hand.'),
            SizedBox(height: 12),
            Text(
              '.bns files stand on open technology, credited and used as-is: '
              'ZIP (PKWARE), DEFLATE/GZIP (RFC 1951/1952), JSON, AES. '
              'The arrangement on top is BNS.',
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 12),
            Text('Whatever today looked like — you showed up. That counts.'),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildMenuBar(ColorScheme colorScheme) {
    return MenuBar(
      style: const MenuStyle(
        elevation: WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      children: [
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.save_outlined, size: 18),
              onPressed: _exportBackup,
              child: const Text('Export backup (.bns)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.folder_open_outlined, size: 18),
              onPressed: _importBackup,
              child: const Text('Import backup (.bns)…'),
            ),
          ],
          child: const Text('File'),
        ),
        SubmenuButton(
          menuChildren: [
            for (int i = 0; i < _destinations.length; i++)
              MenuItemButton(
                leadingIcon: Icon(_destinations[i].icon, size: 18),
                trailingIcon: Text(
                  Keybinds.pretty(Keybinds.defaults[
                          _routeToKeybindId[_destinations[i].route]] ??
                      ''),
                  style: TextStyle(
                      fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
                onPressed: () => _onDestinationSelected(i),
                child: Text(_destinations[i].label),
              ),
          ],
          child: const Text('View'),
        ),
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.favorite_outline, size: 18),
              onPressed: _showAbout,
              child: const Text('About BNS'),
            ),
          ],
          child: const Text('Help'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isDesktopPlatform =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final useDesktopLayout = isDesktopPlatform && size.width >= 820;

    if (!useDesktopLayout) {
      // Narrow or mobile: just the child (original behavior preserved)
      return widget.child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary; // teal relaxing color

    return Row(
      children: [
        // Modern sidebar menu (NavigationRail style but customized for BNS feel)
        Container(
          width: 220,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              right: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(0.4),
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              // Header with logo + app name (modern desktop title area)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Row(
                  children: [
                    Image.asset('assets/icon/bns_logo.png',
                        height: 32, width: 32),
                    const SizedBox(width: 10),
                    Text(
                      'BNS',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PC',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // The actual modern navigation rail destinations
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (int i = 0; i < _destinations.length; i++)
                      _DesktopNavItem(
                        destination: _destinations[i],
                        selected: i == _selectedIndex,
                        onTap: () => _onDestinationSelected(i),
                        primaryColor: primary,
                      ),
                  ],
                ),
              ),

              // Bottom info (PC focused, robust)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Everything stays on your devices.\nPrivate • No cloud • Yours',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Main content area
        Expanded(
          child: Column(
            children: [
              // Optional top modern bar (thin, clean)
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                        color: colorScheme.outlineVariant.withOpacity(0.3)),
                  ),
                ),
                padding: const EdgeInsets.only(left: 4, right: 16),
                child: Row(
                  children: [
                    // Real desktop menu bar: discoverable File/View/Help.
                    _buildMenuBar(colorScheme),
                    const SizedBox(width: 12),
                    Text(
                      _destinations[_selectedIndex].label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    // Gentle orientation: always know what day it is.
                    Text(
                      DateFormat('EEEE, MMMM d').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // The actual screen content
              Expanded(child: widget.child),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesktopDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;
  final String tooltip;

  const _DesktopDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
    required this.tooltip,
  });
}

/// Individual modern nav item with clear "selected" marking.
/// Uses the same relaxing teal coloring as the rest of the app.
class _DesktopNavItem extends StatelessWidget {
  final _DesktopDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final Color primaryColor;

  const _DesktopNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final bg = selected ? primaryColor.withOpacity(0.12) : Colors.transparent;
    final iconColor = selected ? primaryColor : colorScheme.onSurfaceVariant;
    final textColor = selected ? primaryColor : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        message: destination.tooltip,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: iconColor,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      destination.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (selected)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
