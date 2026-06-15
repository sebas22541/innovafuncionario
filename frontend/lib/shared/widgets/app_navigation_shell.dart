import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../features/events/domain/entities/event_record.dart';
import '../../features/events/presentation/screens/events_screen.dart';
import '../../features/events/presentation/screens/user_events_screen.dart';
import '../../features/credentials/presentation/screens/credentials_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/lunches/presentation/screens/lunches_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/permissions/presentation/screens/exit_permits_screen.dart';
import '../../features/qr_scanner/presentation/screens/qr_scanner_screen.dart';
import '../../features/reports/presentation/screens/qr_generation_map_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/users/presentation/screens/users_screen.dart';
import '../models/app_section.dart';
import '../models/app_user.dart';
import 'app_alert.dart';
import 'base64_avatar.dart';
import 'role_portal_shell.dart';

class AppNavigationShell extends StatefulWidget {
  const AppNavigationShell({
    super.key,
    required this.currentUser,
    this.initialSection,
    this.onCurrentUserChanged,
    this.onSectionChanged,
    required this.onLogout,
  });

  final AppUser currentUser;
  final AppSection? initialSection;
  final ValueChanged<AppUser>? onCurrentUserChanged;
  final ValueChanged<AppSection>? onSectionChanged;
  final VoidCallback onLogout;

  @override
  State<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends State<AppNavigationShell> {
  late AppSection _selectedSection;
  EventRecord? _scannerEvent;
  late AppUser _currentUser;
  bool _lunchScannerModeActive = false;
  int _lunchScannerBackToken = 0;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.currentUser;
    _selectedSection = _resolveInitialSection(
      _currentUser,
      widget.initialSection,
    );
  }

  @override
  void didUpdateWidget(covariant AppNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentUser.id != widget.currentUser.id ||
        oldWidget.currentUser.email != widget.currentUser.email) {
      _currentUser = widget.currentUser;

      if (!_visibleSectionsForUser(_currentUser).contains(_selectedSection)) {
        _selectedSection = _defaultSectionForUser(_currentUser);
        widget.onSectionChanged?.call(_selectedSection);
      }
    }
  }

  void _selectSection(AppSection section) {
    if (_selectedSection == section) {
      return;
    }

    setState(() {
      _selectedSection = section;
      if (section != AppSection.lunchScanner) {
        _lunchScannerModeActive = false;
      }
    });
    widget.onSectionChanged?.call(section);
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

    if (section == AppSection.myQr && _currentUser.isExternalUser) {
      _openMyQrDialog();
      return;
    }

    _selectSection(section);
  }

  Future<void> _openMyQrDialog() async {
    if (!_currentUser.hasQr) {
      AppAlert.showWarning(
        context,
        'Tu QR todavia no esta disponible. Vuelve a iniciar sesion.',
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => MyQrDialog(currentUser: _currentUser),
    );
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
    widget.onSectionChanged?.call(AppSection.qrScanner);
  }

  void _handleCurrentUserUpdated(AppUser user) {
    setState(() {
      _currentUser = user;
    });
    widget.onCurrentUserChanged?.call(user);
  }

  void _handleSystemBack() {
    FocusManager.instance.primaryFocus?.unfocus();
    final defaultSection = _defaultSectionForUser(_currentUser);

    if (_selectedSection == AppSection.lunchScanner &&
        _lunchScannerModeActive) {
      setState(() {
        _lunchScannerBackToken++;
        _lunchScannerModeActive = false;
      });
      return;
    }

    if (_selectedSection != defaultSection) {
      _selectSection(defaultSection);
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
      case AppSection.notifications:
        return _currentUser.isAdmin
            ? const NotificationsScreen()
            : SettingsScreen(
                currentUser: _currentUser,
                onUserUpdated: _handleCurrentUserUpdated,
                onLogout: widget.onLogout,
              );
      case AppSection.credentials:
        return _currentUser.isAdmin || _currentUser.isCredentials
            ? CredentialsScreen(currentUser: _currentUser)
            : SettingsScreen(
                currentUser: _currentUser,
                onUserUpdated: _handleCurrentUserUpdated,
                onLogout: widget.onLogout,
              );
      case AppSection.permissionExits:
        return ExitPermitsScreen(currentUser: _currentUser);
      case AppSection.myExitPermits:
        return MyExitPermitsScreen(currentUser: _currentUser);
      case AppSection.exitPermitRequests:
        return ExitPermitRequestsScreen(currentUser: _currentUser);
      case AppSection.lunches:
        return const LunchesAdminScreen();
      case AppSection.lunchScanner:
        return LunchScannerScreen(
          currentUser: _currentUser,
          backToModeSelectionToken: _lunchScannerBackToken,
          onModeActiveChanged: (isActive) {
            if (_lunchScannerModeActive == isActive) {
              return;
            }

            setState(() {
              _lunchScannerModeActive = isActive;
            });
          },
        );
      case AppSection.qrScanner:
        return _currentUser.canUseEventScanner
            ? QrScannerScreen(
                currentUser: _currentUser,
                activeEventId: _scannerEvent?.id,
                activeEventName: _scannerEvent?.name,
                activeEventOffices: _scannerEvent?.offices ?? const [],
                activeEventJobTitles: _scannerEvent?.jobTitles ?? const [],
                activeEventControls: _scannerEvent?.controls ?? const [],
              )
            : UserEventsScreen(
                currentUser: _currentUser,
                viewMode: UserEventsViewMode.attended,
              );
      case AppSection.myQr:
        return RolePortalHomeContent(
          currentUser: _currentUser,
          entries: _portalEntriesForUser(_currentUser),
          onSelected: _handleSectionSelection,
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
    final usePortalShell = !_currentUser.isAdmin && !_currentUser.isCredentials;

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
                onBack: _handleSystemBack,
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
            resizeToAvoidBottomInset: false,
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

class _MobileAppFrame extends StatefulWidget {
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
  State<_MobileAppFrame> createState() => _MobileAppFrameState();
}

class _MobileAppFrameState extends State<_MobileAppFrame> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _openMenu() {
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Future<void> _handleSelected(AppSection section) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffoldState = _scaffoldKey.currentState;

    if (scaffoldState?.isEndDrawerOpen == true) {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    if (!mounted) {
      return;
    }

    widget.onSelected(section);
  }

  Future<void> _handleLogout() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scaffoldState = _scaffoldKey.currentState;

    if (scaffoldState?.isEndDrawerOpen == true) {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    if (!mounted) {
      return;
    }

    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(widget.isFramed ? 38 : 0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppPalette.surface,
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
          resizeToAvoidBottomInset: false,
          backgroundColor: AppPalette.cream,
          endDrawer: _MobileNavigationDrawer(
            currentUser: widget.currentUser,
            selectedSection: widget.selectedSection,
            visibleSections: widget.visibleSections,
            onSelected: _handleSelected,
            onLogout: _handleLogout,
          ),
          body: Column(
            children: [
              _MobileTopBar(
                currentUser: widget.currentUser,
                selectedSection: widget.selectedSection,
                onMenu: _openMenu,
              ),
              Expanded(child: widget.child),
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
    required this.onMenu,
  });

  final AppUser currentUser;
  final AppSection selectedSection;
  final VoidCallback onMenu;

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
              IconButton(
                onPressed: onMenu,
                tooltip: 'Menu',
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileNavigationDrawer extends StatefulWidget {
  const _MobileNavigationDrawer({
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
  State<_MobileNavigationDrawer> createState() =>
      _MobileNavigationDrawerState();
}

class _MobileNavigationDrawerState extends State<_MobileNavigationDrawer> {
  late bool _isAttendanceExpanded;
  late bool _isPermissionsExpanded;

  @override
  void initState() {
    super.initState();
    _isAttendanceExpanded = _isAttendanceSection(widget.selectedSection);
    _isPermissionsExpanded = _isPermissionSection(widget.selectedSection);
  }

  @override
  void didUpdateWidget(covariant _MobileNavigationDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isAttendanceSection(widget.selectedSection) &&
        oldWidget.selectedSection != widget.selectedSection) {
      _isAttendanceExpanded = true;
    }

    if (_isPermissionSection(widget.selectedSection) &&
        oldWidget.selectedSection != widget.selectedSection) {
      _isPermissionsExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final attendanceSections = widget.visibleSections
        .where(_isAttendanceSection)
        .toList(growable: false);
    final permissionSections = widget.visibleSections
        .where(_isPermissionSection)
        .toList(growable: false);
    final leadingSections = widget.visibleSections
        .where(
          (section) =>
              !_isAttendanceSection(section) &&
              !_isPermissionSection(section) &&
              section != AppSection.settings,
        )
        .toList(growable: false);
    final settingsSections = widget.visibleSections
        .where((section) => section == AppSection.settings)
        .toList(growable: false);
    final isAttendanceSelected = _isAttendanceSection(widget.selectedSection);
    final isPermissionsSelected = _isPermissionSection(widget.selectedSection);

    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * 0.84, 340),
      backgroundColor: AppPalette.night,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(32),
          bottomLeft: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    _UserAvatar(currentUser: widget.currentUser, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.currentUser.fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.currentUser.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppPalette.onDarkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final section in leadingSections) ...[
                        _DesktopNavItem(
                          currentUser: widget.currentUser,
                          section: section,
                          isSelected: section == widget.selectedSection,
                          onTap: () => widget.onSelected(section),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (attendanceSections.isNotEmpty) ...[
                        _DesktopNavGroup(
                          label: 'Asistencias',
                          icon: Icons.apps_rounded,
                          isSelected: isAttendanceSelected,
                          isExpanded: _isAttendanceExpanded,
                          onTap: () => setState(() {
                            _isAttendanceExpanded = !_isAttendanceExpanded;
                          }),
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(
                              left: 14,
                              top: 8,
                              bottom: 2,
                            ),
                            child: Column(
                              children: [
                                for (final section in attendanceSections) ...[
                                  _DesktopSubNavItem(
                                    currentUser: widget.currentUser,
                                    section: section,
                                    isSelected:
                                        section == widget.selectedSection,
                                    onTap: () => widget.onSelected(section),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                          crossFadeState: _isAttendanceExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 180),
                        ),
                      ],
                      if (permissionSections.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _DesktopNavGroup(
                          label: 'Permisos',
                          icon: Icons.fact_check_outlined,
                          isSelected: isPermissionsSelected,
                          isExpanded: _isPermissionsExpanded,
                          onTap: () => setState(() {
                            _isPermissionsExpanded = !_isPermissionsExpanded;
                          }),
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(
                              left: 14,
                              top: 8,
                              bottom: 2,
                            ),
                            child: Column(
                              children: [
                                for (final section in permissionSections) ...[
                                  _DesktopSubNavItem(
                                    currentUser: widget.currentUser,
                                    section: section,
                                    isSelected:
                                        section == widget.selectedSection,
                                    onTap: () => widget.onSelected(section),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                          crossFadeState: _isPermissionsExpanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 180),
                        ),
                      ],
                      for (final section in settingsSections) ...[
                        const SizedBox(height: 10),
                        _DesktopNavItem(
                          currentUser: widget.currentUser,
                          section: section,
                          isSelected: section == widget.selectedSection,
                          onTap: () => widget.onSelected(section),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onLogout,
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
      ),
    );
  }
}

class _DesktopSidebar extends StatefulWidget {
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
  State<_DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<_DesktopSidebar> {
  late bool _isAttendanceExpanded;
  late bool _isPermissionsExpanded;

  @override
  void initState() {
    super.initState();
    _isAttendanceExpanded = _isAttendanceSection(widget.selectedSection);
    _isPermissionsExpanded = _isPermissionSection(widget.selectedSection);
  }

  @override
  void didUpdateWidget(covariant _DesktopSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_isAttendanceSection(widget.selectedSection) &&
        oldWidget.selectedSection != widget.selectedSection) {
      _isAttendanceExpanded = true;
    }

    if (_isPermissionSection(widget.selectedSection) &&
        oldWidget.selectedSection != widget.selectedSection) {
      _isPermissionsExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final attendanceSections = widget.visibleSections
        .where(_isAttendanceSection)
        .toList(growable: false);
    final permissionSections = widget.visibleSections
        .where(_isPermissionSection)
        .toList(growable: false);
    final leadingSections = widget.visibleSections
        .where(
          (section) =>
              !_isAttendanceSection(section) &&
              !_isPermissionSection(section) &&
              section != AppSection.settings,
        )
        .toList(growable: false);
    final trailingSections = widget.visibleSections
        .where((section) => section == AppSection.settings)
        .toList(growable: false);
    final isAttendanceSelected = _isAttendanceSection(widget.selectedSection);
    final isPermissionsSelected = _isPermissionSection(widget.selectedSection);

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
                                _UserAvatar(
                                  currentUser: widget.currentUser,
                                  size: 52,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.currentUser.fullName,
                                        style: textTheme.titleMedium?.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.currentUser.email,
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
                          for (final section in leadingSections) ...[
                            _DesktopNavItem(
                              currentUser: widget.currentUser,
                              section: section,
                              isSelected: section == widget.selectedSection,
                              onTap: () => widget.onSelected(section),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (attendanceSections.isNotEmpty) ...[
                            _DesktopNavGroup(
                              label: 'Asistencias',
                              icon: Icons.apps_rounded,
                              isSelected: isAttendanceSelected,
                              isExpanded: _isAttendanceExpanded,
                              onTap: () => setState(() {
                                _isAttendanceExpanded = !_isAttendanceExpanded;
                              }),
                            ),
                            AnimatedCrossFade(
                              firstChild: const SizedBox.shrink(),
                              secondChild: Padding(
                                padding: const EdgeInsets.only(
                                  left: 14,
                                  top: 8,
                                  bottom: 2,
                                ),
                                child: Column(
                                  children: [
                                    for (final section
                                        in attendanceSections) ...[
                                      _DesktopSubNavItem(
                                        currentUser: widget.currentUser,
                                        section: section,
                                        isSelected:
                                            section == widget.selectedSection,
                                        onTap: () => widget.onSelected(section),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                ),
                              ),
                              crossFadeState: _isAttendanceExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 180),
                            ),
                          ],
                          if (permissionSections.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _DesktopNavGroup(
                              label: 'Permisos',
                              icon: Icons.fact_check_outlined,
                              isSelected: isPermissionsSelected,
                              isExpanded: _isPermissionsExpanded,
                              onTap: () => setState(() {
                                _isPermissionsExpanded =
                                    !_isPermissionsExpanded;
                              }),
                            ),
                            AnimatedCrossFade(
                              firstChild: const SizedBox.shrink(),
                              secondChild: Padding(
                                padding: const EdgeInsets.only(
                                  left: 14,
                                  top: 8,
                                  bottom: 2,
                                ),
                                child: Column(
                                  children: [
                                    for (final section
                                        in permissionSections) ...[
                                      _DesktopSubNavItem(
                                        currentUser: widget.currentUser,
                                        section: section,
                                        isSelected:
                                            section == widget.selectedSection,
                                        onTap: () => widget.onSelected(section),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                ),
                              ),
                              crossFadeState: _isPermissionsExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 180),
                            ),
                          ],
                          for (final section in trailingSections) ...[
                            const SizedBox(height: 10),
                            _DesktopNavItem(
                              currentUser: widget.currentUser,
                              section: section,
                              isSelected: section == widget.selectedSection,
                              onTap: () => widget.onSelected(section),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: widget.onLogout,
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

class _DesktopNavGroup extends StatelessWidget {
  const _DesktopNavGroup({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isExpanded;
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
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(24),
            border: isSelected
                ? Border.all(color: Colors.white.withValues(alpha: 0.12))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : AppPalette.onDarkMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppPalette.onDarkMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: isExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: isSelected ? Colors.white : AppPalette.onDarkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopSubNavItem extends StatelessWidget {
  const _DesktopSubNavItem({
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
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.13)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                _sectionIconForUser(currentUser, section),
                size: 20,
                color: isSelected ? Colors.white : AppPalette.onDarkMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _sectionLabelForUser(currentUser, section),
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppPalette.onDarkMuted,
                    fontWeight: FontWeight.w600,
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
      AppSection.notifications,
      AppSection.credentials,
      AppSection.permissionExits,
      AppSection.lunches,
      AppSection.settings,
    ];
  }

  if (user.isControl) {
    return const [
      AppSection.home,
      AppSection.events,
      AppSection.permissionExits,
      AppSection.settings,
    ];
  }

  if (user.isCredentials) {
    return const [
      AppSection.credentials,
      AppSection.permissionExits,
      AppSection.settings,
    ];
  }

  if (user.isLunchControl) {
    return const [AppSection.lunchScanner];
  }

  final sections = [
    AppSection.home,
    AppSection.events,
    AppSection.availableEvents,
    AppSection.myQr,
    if (!_isDirectorJobTitle(user)) AppSection.permissionExits,
    if (!_isDirectorJobTitle(user)) AppSection.myExitPermits,
    if (_isExitPermitApproverUser(user)) AppSection.exitPermitRequests,
    AppSection.settings,
  ];

  return sections;
}

bool _isAttendanceSection(AppSection section) {
  switch (section) {
    case AppSection.events:
    case AppSection.reports:
    case AppSection.map:
    case AppSection.credentials:
      return true;
    case AppSection.home:
    case AppSection.availableEvents:
    case AppSection.permissionExits:
    case AppSection.myExitPermits:
    case AppSection.exitPermitRequests:
    case AppSection.lunches:
    case AppSection.lunchScanner:
    case AppSection.qrScanner:
    case AppSection.myQr:
    case AppSection.users:
    case AppSection.notifications:
    case AppSection.settings:
      return false;
  }
}

bool _isPermissionSection(AppSection section) {
  switch (section) {
    case AppSection.permissionExits:
    case AppSection.myExitPermits:
    case AppSection.exitPermitRequests:
    case AppSection.lunches:
      return true;
    case AppSection.home:
    case AppSection.events:
    case AppSection.availableEvents:
    case AppSection.reports:
    case AppSection.map:
    case AppSection.users:
    case AppSection.notifications:
    case AppSection.credentials:
    case AppSection.qrScanner:
    case AppSection.myQr:
    case AppSection.lunchScanner:
    case AppSection.settings:
      return false;
  }
}

AppSection _defaultSectionForUser(AppUser user) {
  if (user.isLunchControl) {
    return AppSection.lunchScanner;
  }

  if (user.isCredentials) {
    return AppSection.credentials;
  }

  return AppSection.home;
}

AppSection _resolveInitialSection(AppUser user, AppSection? initialSection) {
  if (initialSection == null) {
    return _defaultSectionForUser(user);
  }

  if (user.isExternalUser && initialSection == AppSection.myQr) {
    return _defaultSectionForUser(user);
  }

  if (_visibleSectionsForUser(user).contains(initialSection)) {
    return initialSection;
  }

  if (initialSection == AppSection.qrScanner && user.canUseEventScanner) {
    return initialSection;
  }

  return _defaultSectionForUser(user);
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
      case AppSection.myQr:
        return 'Mi QR';
      case AppSection.permissionExits:
        return 'Formulario de salida';
      case AppSection.myExitPermits:
        return 'Mis solicitudes';
      case AppSection.exitPermitRequests:
        return 'Solicitudes recibidas';
      case AppSection.settings:
        return 'Perfil';
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
    case AppSection.myQr:
      return 'Mi QR';
    case AppSection.myExitPermits:
      return 'Mis solicitudes';
    case AppSection.permissionExits:
      if (_isDirectorExitPermitUser(user)) {
        return 'Solicitudes recibidas';
      }

      return 'Formulario de salida';
    case AppSection.exitPermitRequests:
      return 'Solicitudes recibidas';
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
      case AppSection.myQr:
        return 'Mi QR';
      case AppSection.permissionExits:
        return _isDirectorExitPermitUser(user)
            ? 'Solicitudes recibidas'
            : 'Salidas';
      case AppSection.myExitPermits:
        return 'Mis solicitudes';
      case AppSection.exitPermitRequests:
        return 'Solicitudes recibidas';
      case AppSection.settings:
        return 'Perfil';
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
      case AppSection.myQr:
        return 'Mi QR';
      case AppSection.permissionExits:
        return _isDirectorExitPermitUser(user)
            ? 'Solicitudes recibidas'
            : 'Salidas';
      case AppSection.myExitPermits:
        return 'Mis solicitudes';
      case AppSection.exitPermitRequests:
        return 'Solicitudes recibidas';
      case AppSection.settings:
        return 'Perfil';
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
      case AppSection.myQr:
        return Icons.qr_code_2_rounded;
      case AppSection.permissionExits:
        return _isExitPermitApproverUser(user)
            ? Icons.fact_check_outlined
            : Icons.exit_to_app_rounded;
      case AppSection.myExitPermits:
        return Icons.assignment_outlined;
      case AppSection.exitPermitRequests:
        return Icons.assignment_turned_in_outlined;
      case AppSection.settings:
        return Icons.person_outline_rounded;
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
      case AppSection.myQr:
        return Icons.qr_code_2_rounded;
      case AppSection.myExitPermits:
        return Icons.assignment_outlined;
      case AppSection.settings:
        return Icons.person_outline_rounded;
      case AppSection.exitPermitRequests:
        return Icons.assignment_turned_in_outlined;
      default:
        return section.icon;
    }
  }

  return section.icon;
}

bool _isExitPermitApproverUser(AppUser user) {
  const bossCodes = {
    'CA018',
    'CA015',
    'CA014',
    'CA013',
    'CA012',
    'CA011',
    'CA010',
  };
  final cargoCodigo = user.cargoCodigo?.trim().toUpperCase();
  final cargo = user.cargo
      .toLowerCase()
      .replaceAll('Ã¡', 'a')
      .replaceAll('Ã©', 'e')
      .replaceAll('Ã­', 'i')
      .replaceAll('Ã³', 'o')
      .replaceAll('Ãº', 'u');

  return (cargoCodigo != null && bossCodes.contains(cargoCodigo)) ||
      cargo.contains('jefe') ||
      _isDirectorExitPermitUser(user);
}

bool _isDirectorExitPermitUser(AppUser user) {
  final officeCode = user.officeCode?.trim();
  return _isDirectorOfficeCode(officeCode) && _isDirectorJobTitle(user);
}

bool _isDirectorJobTitle(AppUser user) {
  final cargo = user.cargo
      .toLowerCase()
      .replaceAll('ÃƒÂ¡', 'a')
      .replaceAll('ÃƒÂ©', 'e')
      .replaceAll('ÃƒÂ­', 'i')
      .replaceAll('ÃƒÂ³', 'o')
      .replaceAll('ÃƒÂº', 'u');

  return cargo.contains('director') || cargo.contains('direcctor');
}

bool _isDirectorOfficeCode(String? code) {
  const directorOfficeCodes = {
    '0.1',
    '0.2',
    '0.5',
    '1.1',
    '1.3',
    '2.1',
    '2.2',
    '3.3',
    '3.4',
    '4.1',
    '4.2',
    '5.1',
    '5.2',
    '5.3',
    '5.5',
    '6.1',
    '6.2',
    '6.3',
    '6.4',
    '7.2',
    '7.3',
    '8.1',
    '8.2',
    '8.3',
    '9.1',
    '9.2',
    '10.1',
    '10.2',
    '10.3',
    '10.4',
    '11.1',
    '11.2',
    '11.4',
    '12.1',
    '12.2',
  };

  return code != null && directorOfficeCodes.contains(code);
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
