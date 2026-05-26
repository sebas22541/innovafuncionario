import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../features/events/domain/entities/event_record.dart';
import '../../features/events/presentation/screens/events_screen.dart';
import '../../features/events/presentation/screens/user_events_screen.dart';
import '../../features/credentials/presentation/screens/credentials_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/qr_scanner/presentation/screens/qr_scanner_screen.dart';
import '../../features/reports/presentation/screens/qr_generation_map_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/users/presentation/screens/users_screen.dart';
import '../models/app_section.dart';
import '../models/app_user.dart';
import 'base64_avatar.dart';
import 'role_portal_shell.dart';

class AppNavigationShell extends StatefulWidget {
  const AppNavigationShell({
    super.key,
    required this.currentUser,
    required this.onLogout,
  });

  final AppUser currentUser;
  final VoidCallback onLogout;

  @override
  State<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends State<AppNavigationShell> {
  late AppSection _selectedSection;
  EventRecord? _scannerEvent;
  late AppUser _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.currentUser;
    _selectedSection = _defaultSectionForUser(_currentUser);
  }

  @override
  void didUpdateWidget(covariant AppNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentUser.id != widget.currentUser.id ||
        oldWidget.currentUser.email != widget.currentUser.email) {
      _currentUser = widget.currentUser;

      if (!_visibleSectionsForUser(_currentUser).contains(_selectedSection)) {
        _selectedSection = _defaultSectionForUser(_currentUser);
      }
    }
  }

  void _selectSection(AppSection section) {
    if (_selectedSection == section) {
      return;
    }

    setState(() {
      _selectedSection = section;
    });
  }

  void _handleSectionSelection(AppSection section) {
    if (!_visibleSectionsForUser(_currentUser).contains(section) &&
        section != AppSection.qrScanner) {
      return;
    }

    if (section == AppSection.qrScanner) {
      if (!_currentUser.canUseEventScanner) {
        return;
      }

      _openScanner();
      return;
    }

    _selectSection(section);
  }

  void _openScanner() {
    _openScannerForEvent(null);
  }

  void _openScannerForEvent(EventRecord? event) {
    final hasSameEvent =
        _selectedSection == AppSection.qrScanner &&
        _scannerEvent?.id == event?.id;

    if (hasSameEvent) {
      return;
    }

    setState(() {
      _scannerEvent = event;
      _selectedSection = AppSection.qrScanner;
    });
  }

  void _handleCurrentUserUpdated(AppUser user) {
    setState(() {
      _currentUser = user;
    });
  }

  void _handleSystemBack() {
    FocusManager.instance.primaryFocus?.unfocus();

    if (_selectedSection != AppSection.home) {
      _selectSection(AppSection.home);
    }
  }

  Widget _buildContent() {
    switch (_selectedSection) {
      case AppSection.home:
        return _currentUser.isAdmin
            ? const HomeScreen()
            : RolePortalHomeContent(
                currentUser: _currentUser,
                entries: _portalEntriesForUser(_currentUser),
                onSelected: _handleSectionSelection,
              );
      case AppSection.events:
        return _currentUser.canUseEventsPanel
            ? EventsScreen(
                currentUser: _currentUser,
                onOpenScanner: _openScannerForEvent,
              )
            : UserEventsScreen(
                currentUser: _currentUser,
                viewMode: UserEventsViewMode.attended,
              );
      case AppSection.availableEvents:
        return UserEventsScreen(
          currentUser: _currentUser,
          viewMode: UserEventsViewMode.available,
        );
      case AppSection.reports:
        return _currentUser.isAdmin
            ? const ReportsScreen()
            : UserEventsScreen(
                currentUser: _currentUser,
                viewMode: UserEventsViewMode.attended,
              );
      case AppSection.map:
        return _currentUser.isAdmin
            ? QrGenerationMapScreen(currentUser: _currentUser)
            : UserEventsScreen(
                currentUser: _currentUser,
                viewMode: UserEventsViewMode.attended,
              );
      case AppSection.users:
        return _currentUser.isAdmin
            ? UsersScreen(currentUser: _currentUser)
            : SettingsScreen(
                currentUser: _currentUser,
                onUserUpdated: _handleCurrentUserUpdated,
                onLogout: widget.onLogout,
              );
      case AppSection.credentials:
        return _currentUser.isAdmin
            ? CredentialsScreen(currentUser: _currentUser)
            : SettingsScreen(
                currentUser: _currentUser,
                onUserUpdated: _handleCurrentUserUpdated,
                onLogout: widget.onLogout,
              );
      case AppSection.qrScanner:
        return _currentUser.canUseEventScanner
            ? QrScannerScreen(
                currentUser: _currentUser,
                activeEventId: _scannerEvent?.id,
                activeEventName: _scannerEvent?.name,
                activeEventOffices: _scannerEvent?.offices ?? const [],
                activeEventControls: _scannerEvent?.controls ?? const [],
              )
            : UserEventsScreen(
                currentUser: _currentUser,
                viewMode: UserEventsViewMode.attended,
              );
      case AppSection.settings:
        return SettingsScreen(
          currentUser: _currentUser,
          onUserUpdated: _handleCurrentUserUpdated,
          onLogout: widget.onLogout,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleSections = _visibleSectionsForUser(_currentUser);
    final usePortalShell = !_currentUser.isAdmin;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;
        final isFramed = !isDesktop && constraints.maxWidth >= 700;
        final useFloatingFrame = isDesktop || isFramed;
        final frameHeight = isFramed
            ? math.min(constraints.maxHeight - 40, 940.0)
            : constraints.maxHeight;
        final animatedContent = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: [
                for (final child in previousChildren)
                  IgnorePointer(ignoring: true, child: child),
                ?currentChild,
              ],
            );
          },
          child: KeyedSubtree(
            key: ValueKey(_selectedSection),
            child: _buildContent(),
          ),
        );
        final shellContent = usePortalShell
            ? RolePortalShell(
                isFramed: useFloatingFrame,
                currentUser: _currentUser,
                selectedSection: _selectedSection,
                entries: _portalEntriesForUser(_currentUser),
                onSelected: _handleSectionSelection,
                onLogout: widget.onLogout,
                child: animatedContent,
              )
            : isDesktop
            ? _DesktopShell(
                currentUser: _currentUser,
                selectedSection: _selectedSection,
                visibleSections: visibleSections,
                onSelected: _handleSectionSelection,
                onLogout: widget.onLogout,
                child: animatedContent,
              )
            : _MobileAppFrame(
                isFramed: isFramed,
                currentUser: _currentUser,
                selectedSection: _selectedSection,
                visibleSections: visibleSections,
                onSelected: _handleSectionSelection,
                onLogout: widget.onLogout,
                child: animatedContent,
              );
        final framedShellWidth = usePortalShell
            ? 430.0
            : (isDesktop ? 1280.0 : 480.0);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              _handleSystemBack();
            }
          },
          child: Scaffold(
            backgroundColor: AppPalette.cream,
            body: Stack(
              children: [
                const Positioned(
                  top: -120,
                  right: -60,
                  child: _BackgroundOrb(size: 300, color: Color(0x146D56A0)),
                ),
                const Positioned(
                  left: -100,
                  bottom: -20,
                  child: _BackgroundOrb(size: 260, color: Color(0x127D67B1)),
                ),
                SafeArea(
                  minimum: EdgeInsets.all(
                    useFloatingFrame ? (isDesktop ? 22 : 12) : 0,
                  ),
                  child: useFloatingFrame
                      ? Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: framedShellWidth,
                            ),
                            child: SizedBox(
                              height: frameHeight,
                              child: shellContent,
                            ),
                          ),
                        )
                      : SizedBox.expand(child: shellContent),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({
    required this.currentUser,
    required this.selectedSection,
    required this.visibleSections,
    required this.onSelected,
    required this.onLogout,
    required this.child,
  });

  final AppUser currentUser;
  final AppSection selectedSection;
  final List<AppSection> visibleSections;
  final ValueChanged<AppSection> onSelected;
  final VoidCallback onLogout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: _DesktopSidebar(
            currentUser: currentUser,
            selectedSection: selectedSection,
            visibleSections: visibleSections,
            onSelected: onSelected,
            onLogout: onLogout,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(38),
              border: Border.all(color: AppPalette.line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1554407E),
                  blurRadius: 30,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(38),
              child: Column(
                children: [
                  _DesktopHeader(
                    currentUser: currentUser,
                    selectedSection: selectedSection,
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: AppPalette.cream.withValues(alpha: 0.55),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileAppFrame extends StatelessWidget {
  const _MobileAppFrame({
    required this.isFramed,
    required this.currentUser,
    required this.selectedSection,
    required this.visibleSections,
    required this.onSelected,
    required this.onLogout,
    required this.child,
  });

  final bool isFramed;
  final AppUser currentUser;
  final AppSection selectedSection;
  final List<AppSection> visibleSections;
  final ValueChanged<AppSection> onSelected;
  final VoidCallback onLogout;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(isFramed ? 38 : 0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: borderRadius,
        border: isFramed ? Border.all(color: AppPalette.line) : null,
        boxShadow: isFramed
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
        child: ColoredBox(
          color: AppPalette.cream,
          child: Column(
            children: [
              _MobileTopBar(
                currentUser: currentUser,
                selectedSection: selectedSection,
                onLogout: onLogout,
              ),
              Expanded(child: child),
              _MobileBottomBar(
                currentUser: currentUser,
                selectedSection: selectedSection,
                visibleSections: visibleSections,
                onSelected: onSelected,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.currentUser,
    required this.selectedSection,
    required this.onLogout,
  });

  final AppUser currentUser;
  final AppSection selectedSection;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: const BoxDecoration(
        color: AppPalette.night,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -6,
            right: -4,
            child: _BackgroundOrb(size: 86, color: Color(0x1BFFFFFF)),
          ),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _BrandLogo(height: 56),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones',
                color: AppPalette.surface,
                onSelected: (value) {
                  if (value == 'logout') {
                    onLogout();
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Text('Cerrar sesion'),
                  ),
                ],
                icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileBottomBar extends StatelessWidget {
  const _MobileBottomBar({
    required this.currentUser,
    required this.selectedSection,
    required this.visibleSections,
    required this.onSelected,
  });

  final AppUser currentUser;
  final AppSection selectedSection;
  final List<AppSection> visibleSections;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    const minItemWidth = 76.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(top: BorderSide(color: AppPalette.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = math.max(
            minItemWidth,
            constraints.maxWidth / visibleSections.length,
          );

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                for (final section in visibleSections)
                  SizedBox(
                    width: itemWidth,
                    child: _BottomBarItem(
                      currentUser: currentUser,
                      section: section,
                      isSelected: section == selectedSection,
                      onTap: () => onSelected(section),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.currentUser,
    required this.selectedSection,
    required this.visibleSections,
    required this.onSelected,
    required this.onLogout,
  });

  final AppUser currentUser;
  final AppSection selectedSection;
  final List<AppSection> visibleSections;
  final ValueChanged<AppSection> onSelected;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.night,
        borderRadius: BorderRadius.circular(38),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A54407E),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(38),
        child: Stack(
          children: [
            const Positioned(
              top: -14,
              right: -8,
              child: _BackgroundOrb(size: 96, color: Color(0x1DFFFFFF)),
            ),
            const Positioned(
              bottom: 110,
              left: -24,
              child: _BackgroundOrb(size: 130, color: Color(0x14D7CDEA)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(child: _BrandLogo(height: 74)),
                          const SizedBox(height: 26),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              children: [
                                _UserAvatar(currentUser: currentUser, size: 52),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentUser.fullName,
                                        style: textTheme.titleMedium?.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentUser.email,
                                        style: textTheme.bodySmall?.copyWith(
                                          color: AppPalette.onDarkMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          for (final section in visibleSections) ...[
                            _DesktopNavItem(
                              currentUser: currentUser,
                              section: section,
                              isSelected: section == selectedSection,
                              onTap: () => onSelected(section),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onLogout,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Cerrar sesion'),
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
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.currentUser,
    required this.selectedSection,
  });

  final AppUser currentUser;
  final AppSection selectedSection;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(bottom: BorderSide(color: AppPalette.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _sectionTitleForUser(currentUser, selectedSection),
              style: textTheme.headlineMedium?.copyWith(fontSize: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBarItem extends StatelessWidget {
  const _BottomBarItem({
    required this.currentUser,
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final AppUser currentUser;
  final AppSection section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = AppPalette.orange;
    const inactiveColor = AppPalette.muted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppPalette.orangeSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _sectionIconForUser(currentUser, section),
                size: 22,
                color: isSelected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 6),
              Text(
                _sectionLabelForUser(currentUser, section),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavItem extends StatelessWidget {
  const _DesktopNavItem({
    required this.currentUser,
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final AppUser currentUser;
  final AppSection section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: isSelected
                ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                _sectionIconForUser(currentUser, section),
                color: isSelected ? Colors.white : AppPalette.onDarkMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _sectionLabelForUser(currentUser, section),
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppPalette.onDarkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundOrb extends StatelessWidget {
  const _BackgroundOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  const _BrandLogo({required this.height});

  final double height;

  static const _assetPath = 'assets/images/escuBla.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _assetPath,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Text(
          'EscuBla',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        );
      },
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.currentUser, required this.size});

  final AppUser currentUser;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Base64Avatar(
      size: size,
      fallbackLabel: currentUser.fullName,
      photoSource: currentUser.fotoUrl,
      borderRadius: BorderRadius.circular(size * 0.34),
    );
  }
}

List<AppSection> _visibleSectionsForUser(AppUser user) {
  if (user.isAdmin) {
    return const [
      AppSection.home,
      AppSection.events,
      AppSection.reports,
      AppSection.map,
      AppSection.users,
      AppSection.credentials,
      AppSection.settings,
    ];
  }

  if (user.isControl) {
    return const [
      AppSection.home,
      AppSection.events,
      AppSection.qrScanner,
      AppSection.settings,
    ];
  }

  return const [
    AppSection.home,
    AppSection.events,
    AppSection.availableEvents,
    AppSection.settings,
  ];
}

AppSection _defaultSectionForUser(AppUser user) {
  return AppSection.home;
}

String _sectionTitleForUser(AppUser user, AppSection section) {
  if (user.isAdmin) {
    return section.title;
  }

  if (user.isControl) {
    switch (section) {
      case AppSection.home:
        return 'Inicio';
      case AppSection.events:
        return 'Eventos';
      case AppSection.qrScanner:
        return 'Escanear QR';
      case AppSection.settings:
        return 'Mi perfil';
      default:
        return section.title;
    }
  }

  switch (section) {
    case AppSection.home:
      return 'Inicio';
    case AppSection.events:
      return 'Eventos asistidos';
    case AppSection.availableEvents:
      return 'Eventos programados';
    case AppSection.settings:
      return 'Mi perfil';
    default:
      return section.title;
  }
}

String _sectionLabelForUser(AppUser user, AppSection section) {
  if (user.isControl) {
    switch (section) {
      case AppSection.home:
        return 'Inicio';
      case AppSection.qrScanner:
        return 'Escanear QR';
      case AppSection.settings:
        return 'Mi perfil';
      default:
        return section.label;
    }
  }

  if (user.isExternalUser) {
    switch (section) {
      case AppSection.home:
        return 'Inicio';
      case AppSection.events:
        return 'Eventos asistidos';
      case AppSection.availableEvents:
        return 'Eventos programados';
      case AppSection.settings:
        return 'Mi perfil';
      default:
        return section.label;
    }
  }

  return section.label;
}

IconData _sectionIconForUser(AppUser user, AppSection section) {
  if (user.isControl) {
    switch (section) {
      case AppSection.home:
        return Icons.home_rounded;
      case AppSection.events:
        return Icons.event_note_rounded;
      case AppSection.qrScanner:
        return Icons.qr_code_scanner_rounded;
      case AppSection.settings:
        return Icons.edit_rounded;
      default:
        return section.icon;
    }
  }

  if (user.isExternalUser) {
    switch (section) {
      case AppSection.home:
        return Icons.home_rounded;
      case AppSection.events:
        return Icons.event_available_rounded;
      case AppSection.availableEvents:
        return Icons.event_note_rounded;
      case AppSection.settings:
        return Icons.edit_rounded;
      default:
        return section.icon;
    }
  }

  return section.icon;
}

List<PortalNavEntry> _portalEntriesForUser(AppUser user) {
  return _visibleSectionsForUser(user)
      .map(
        (section) => PortalNavEntry(
          section: section,
          label: _sectionLabelForUser(user, section),
          icon: _sectionIconForUser(user, section),
        ),
      )
      .toList(growable: false);
}
