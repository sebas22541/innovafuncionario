import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../models/app_section.dart';
import '../models/app_user.dart';
import 'base64_avatar.dart';

class PortalNavEntry {
  const PortalNavEntry({
    required this.section,
    required this.label,
    required this.icon,
  });

  final AppSection section;
  final String label;
  final IconData icon;
}

class RolePortalShell extends StatefulWidget {
  const RolePortalShell({
    super.key,
    required this.isFramed,
    required this.currentUser,
    required this.selectedSection,
    required this.entries,
    required this.onSelected,
    required this.onLogout,
    required this.child,
  });

  final bool isFramed;
  final AppUser currentUser;
  final AppSection selectedSection;
  final List<PortalNavEntry> entries;
  final ValueChanged<AppSection> onSelected;
  final VoidCallback onLogout;
  final Widget child;

  @override
  State<RolePortalShell> createState() => _RolePortalShellState();
}

class _RolePortalShellState extends State<RolePortalShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool get _isHome => widget.selectedSection == AppSection.home;

  PortalNavEntry get _currentEntry {
    for (final entry in widget.entries) {
      if (entry.section == widget.selectedSection) {
        return entry;
      }
    }

    return widget.entries.first;
  }

  void _openDrawer() {
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _handleSectionTap(AppSection section) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).maybePop();

    if (!mounted) {
      return;
    }

    widget.onSelected(section);
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(widget.isFramed ? 38 : 0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
        border: widget.isFramed ? Border.all(color: AppPalette.line) : null,
        boxShadow: widget.isFramed
            ? const [
                BoxShadow(
                  color: Color(0x1854407E),
                  blurRadius: 36,
                  offset: Offset(0, 16),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: _isHome ? Colors.white : AppPalette.night,
          drawerScrimColor: Colors.black.withValues(alpha: 0.28),
          drawer: _PortalDrawer(
            currentUser: widget.currentUser,
            selectedSection: widget.selectedSection,
            entries: widget.entries,
            onSelected: _handleSectionTap,
            onLogout: widget.onLogout,
          ),
          body: _isHome
              ? Column(
                  children: [
                    _PortalHomeTopBar(onMenu: _openDrawer),
                    Expanded(child: widget.child),
                  ],
                )
              : Column(
                  children: [
                    _PortalInnerHeader(
                      currentUser: widget.currentUser,
                      entry: _currentEntry,
                      onBack: () => widget.onSelected(AppSection.home),
                      onMenu: _openDrawer,
                    ),
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(38),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(38),
                          ),
                          child: ColoredBox(
                            color: AppPalette.cream,
                            child: widget.child,
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

class RolePortalHomeContent extends StatelessWidget {
  const RolePortalHomeContent({
    super.key,
    required this.currentUser,
    required this.entries,
    required this.onSelected,
  });

  final AppUser currentUser;
  final List<PortalNavEntry> entries;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final actions = entries
        .where((entry) => entry.section != AppSection.home)
        .toList(growable: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 26, 18, 32),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final greetingTextWidth = math
              .min(constraints.maxWidth - 112, 280.0)
              .clamp(180.0, 280.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 14,
                children: [
                  Base64Avatar(
                    size: 82,
                    fallbackLabel: currentUser.fullName,
                    photoSource: currentUser.fotoUrl,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: greetingTextWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Hola',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: Colors.black87, fontSize: 26),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentUser.fullName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text.rich(
                textAlign: TextAlign.center,
                TextSpan(
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                  ),
                  children: const [
                    TextSpan(text: 'Que quieres hacer hoy'),
                    TextSpan(
                      text: ' ?',
                      style: TextStyle(color: Color(0xFFE85487)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F1F5),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columnCount = constraints.maxWidth >= 320 ? 3 : 2;
                    const spacing = 12.0;
                    final cardWidth =
                        (constraints.maxWidth - (spacing * (columnCount - 1))) /
                        columnCount;

                    return Wrap(
                      spacing: spacing,
                      runSpacing: 16,
                      children: [
                        for (final entry in actions)
                          SizedBox(
                            width: cardWidth,
                            child: _PortalServiceCard(
                              entry: entry,
                              onTap: () => onSelected(entry.section),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PortalHomeTopBar extends StatelessWidget {
  const _PortalHomeTopBar({required this.onMenu});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      color: AppPalette.night,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              const _CochalLogo(height: 32),
              const Spacer(),
              IconButton(
                onPressed: onMenu,
                icon: const Icon(
                  Icons.menu_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
          const IgnorePointer(child: _InlogLogo(height: 60)),
        ],
      ),
    );
  }
}

class _PortalInnerHeader extends StatelessWidget {
  const _PortalInnerHeader({
    required this.currentUser,
    required this.entry,
    required this.onBack,
    required this.onMenu,
  });

  final AppUser currentUser;
  final PortalNavEntry entry;
  final VoidCallback onBack;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.night,
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: onBack,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
                label: const Text(
                  'Atras',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              const Spacer(),
              Base64Avatar(
                size: 36,
                fallbackLabel: currentUser.fullName,
                photoSource: currentUser.fotoUrl,
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: onMenu,
                icon: const Icon(
                  Icons.menu_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(entry.icon, size: 30, color: AppPalette.night),
          ),
          const SizedBox(height: 8),
          Text(
            entry.label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalServiceCard extends StatelessWidget {
  const _PortalServiceCard({required this.entry, required this.onTap});

  final PortalNavEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(entry.icon, size: 32, color: AppPalette.night),
              ),
              const SizedBox(height: 8),
              Text(
                entry.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalDrawer extends StatelessWidget {
  const _PortalDrawer({
    required this.currentUser,
    required this.selectedSection,
    required this.entries,
    required this.onSelected,
    required this.onLogout,
  });

  final AppUser currentUser;
  final AppSection selectedSection;
  final List<PortalNavEntry> entries;
  final ValueChanged<AppSection> onSelected;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final menuEntries = entries
        .where((entry) => entry.section != AppSection.settings)
        .toList(growable: false);
    PortalNavEntry? settingsEntry;

    for (final entry in entries) {
      if (entry.section == AppSection.settings) {
        settingsEntry = entry;
        break;
      }
    }

    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * 0.84, 340),
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Base64Avatar(
                  size: 110,
                  fallbackLabel: currentUser.fullName,
                  photoSource: currentUser.fotoUrl,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  currentUser.fullName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  currentUser.email,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppPalette.muted,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              for (final entry in menuEntries) ...[
                _PortalDrawerItem(
                  icon: entry.icon,
                  label: entry.label,
                  isSelected: selectedSection == entry.section,
                  onTap: () => onSelected(entry.section),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 14),
              Container(height: 1, color: AppPalette.line),
              const SizedBox(height: 18),
              Text(
                'Otras opciones',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              if (settingsEntry != null) ...[
                _PortalDrawerItem(
                  icon: Icons.edit_rounded,
                  label: 'Mi perfil',
                  isSelected: selectedSection == AppSection.settings,
                  onTap: () => onSelected(AppSection.settings),
                ),
                const SizedBox(height: 8),
              ],
              const Spacer(),
              _PortalDrawerItem(
                icon: Icons.logout_rounded,
                label: 'Cerrar sesion',
                isSelected: false,
                onTap: onLogout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalDrawerItem extends StatelessWidget {
  const _PortalDrawerItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppPalette.orange : Colors.black87;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 16,
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

class _CochalLogo extends StatelessWidget {
  const _CochalLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * 3.5,
      height: height,
      child: Image.asset(
        'assets/images/cochal.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            'Cochal',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          );
        },
      ),
    );
  }
}

class _InlogLogo extends StatelessWidget {
  const _InlogLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * 1.75,
      height: height,
      child: Image.asset(
        'assets/images/inlog.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.check_rounded,
            size: height,
            color: const Color(0xFFE85487),
          );
        },
      ),
    );
  }
}
