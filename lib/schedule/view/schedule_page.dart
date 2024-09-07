import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:rtu_mirea_app/presentation/theme.dart';
import 'package:rtu_mirea_app/presentation/typography.dart';
import 'package:rtu_mirea_app/schedule/bloc/schedule_bloc.dart';
import 'package:rtu_mirea_app/schedule/models/models.dart';
import 'package:rtu_mirea_app/schedule/widgets/widgets.dart';
import 'package:rtu_mirea_app/stories/bloc/stories_bloc.dart';
import 'package:rtu_mirea_app/stories/view/stories_view.dart';
import 'package:university_app_server_api/client.dart';
import 'package:collection/collection.dart';
import 'package:expandable_page_view/expandable_page_view.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  static const int maxLessonsPerDay = 7;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  late final PageController _pageController;
  late final ScrollController _scrollController;
  late final ScheduleBloc _bloc;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: Calendar.getPageIndex(Calendar.getNowWithoutTime()),
    );
    _scrollController = ScrollController();
    _bloc = context.read<ScheduleBloc>();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();

    super.dispose();
  }

  String get _appBarTitle {
    final scheduleState = context.read<ScheduleBloc>().state.selectedSchedule;

    switch (scheduleState.runtimeType) {
      case SelectedGroupSchedule:
        return (scheduleState as SelectedGroupSchedule).group.name;
      case SelectedTeacherSchedule:
        return _formatTeacherName((scheduleState as SelectedTeacherSchedule).teacher.name);
      case SelectedClassroomSchedule:
        return (scheduleState as SelectedClassroomSchedule).classroom.name;
      default:
        return 'Расписание';
    }
  }

  String _formatTeacherName(String fullName) {
    final nameParts = fullName.split(' ');
    if (nameParts.length == 3) {
      return '${nameParts[0]} ${nameParts[1][0]}. ${nameParts[2][0]}.';
    } else if (nameParts.length == 2) {
      return '${nameParts[0]} ${nameParts[1][0]}.';
    } else {
      return fullName;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ScheduleBloc, ScheduleState>(
      listener: (context, state) {
        if (state.status == ScheduleStatus.failure) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ошибка при загрузке расписания'),
            ),
          );
        }
      },
      buildWhen: (previous, current) => current.status != ScheduleStatus.failure && current.selectedSchedule != null,
      builder: (context, state) {
        if (state.status == ScheduleStatus.loading) {
          return const Center(child: CircularProgressIndicator());
        } else if (state.selectedSchedule == null) {
          return NoSelectedScheduleMessage(onTap: () {
            context.go('/schedule/search');
          });
        } else if (state.status == ScheduleStatus.failure) {
          return LoadingErrorMessage(onTap: () {
            context.go('/schedule/search');
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_appBarTitle),
            actions: [
              _buildAddGroupButton(context),
              _buildSettingsButton(context),
              _buildViewToggleButton(),
            ],
          ),
          body: AnimatedSwitcher(
            duration: 300.ms,
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: animation.drive(
                    Tween<Offset>(
                      begin: const Offset(0.0, 0.1),
                      end: Offset.zero,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: state.isListModeEnabled
                ? KeyedSubtree(
                    key: const ValueKey('list_mode'),
                    child: _buildListMode(state),
                  )
                : KeyedSubtree(
                    key: const ValueKey('calendar_mode'),
                    child: _buildCalendarMode(state),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildAddGroupButton(BuildContext context) {
    return IconButton(
      icon: HugeIcon(
        icon: HugeIcons.strokeRoundedAddSquare,
        size: 24,
        color: AppTheme.colorsOf(context).active,
      ),
      tooltip: 'Добавить группу',
      onPressed: () => context.go('/schedule/search'),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return IconButton(
      icon: HugeIcon(
        icon: HugeIcons.strokeRoundedSettings02,
        size: 24,
        color: AppTheme.colorsOf(context).active,
      ),
      tooltip: 'Управление расписанием',
      onPressed: () => context.go('/profile'),
    );
  }

  Widget _buildViewToggleButton() {
    return TextButton(
      onPressed: () {
        _bloc.add(const ToggleListMode());
      },
      style: TextButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(16.0),
      ),
      child: AnimatedSwitcher(
        duration: 300.ms,
        transitionBuilder: (Widget child, Animation<double> animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        child: HugeIcon(
          key: ValueKey<bool>(_bloc.state.isListModeEnabled),
          icon: _bloc.state.isListModeEnabled ? HugeIcons.strokeRoundedListView : HugeIcons.strokeRoundedCalendar02,
          size: 24,
          color: AppTheme.colorsOf(context).active,
        ),
      ),
    );
  }

  Map<DateTime, List<SchedulePart>> _groupLessonsByDay(List<SchedulePart> scheduleParts) {
    final Map<DateTime, List<SchedulePart>> lessonsByDay = {};

    for (final part in scheduleParts) {
      for (final date in part.dates) {
        lessonsByDay.update(
          date,
          (existing) => existing..add(part),
          ifAbsent: () => [part],
        );
      }
    }

    return Map.fromEntries(lessonsByDay.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  Widget _buildListMode(ScheduleState state) {
    final lessonsByDay = _groupLessonsByDay(state.selectedSchedule?.schedule ?? []);

    final today = Calendar.getNowWithoutTime();
    final filteredLessonsByDay = lessonsByDay.keys
        .where((day) => day.isAfter(today) || day.isAtSameMomentAs(today))
        .map((day) => MapEntry(day, lessonsByDay[day]))
        .toList();

    return ListView.builder(
      controller: _scrollController,
      itemCount: filteredLessonsByDay.length,
      itemBuilder: (context, index) {
        final day = filteredLessonsByDay[index].key;
        final lessons = filteredLessonsByDay[index].value?.whereType<LessonSchedulePart>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lessons?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 18.0, left: 24.0, bottom: 14),
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedCalendar01,
                      color: AppTheme.colorsOf(context).deactive,
                      size: 17.5,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEEE, d MMMM', 'ru').format(day),
                      style: AppTextStyle.chip.copyWith(
                        color: AppTheme.colorsOf(context).deactive,
                      ),
                    ),
                  ],
                ),
              ),
            ...lessons?.map((lessonPart) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: LessonCard(
                        lesson: lessonPart,
                        onTap: (lesson) {
                          context.go('/schedule/details', extra: (lesson, day));
                        },
                      ),
                    )) ??
                [],
          ],
        );
      },
    );
  }

  Widget _buildCalendarMode(ScheduleState state) {
    return NestedScrollView(
      headerSliverBuilder: (_, __) => [
        _buildSliverAppBar(),
        if (!state.isListModeEnabled)
          SliverToBoxAdapter(
            child: Calendar(
              pageViewController: _pageController,
              schedule: state.selectedSchedule?.schedule ?? [],
              comments: state.comments,
              showCommentsIndicators: state.showCommentsIndicators,
            ),
          ),
      ],
      body: _buildPageView(state),
    );
  }

  Widget _buildSliverAppBar() {
    return BlocBuilder<StoriesBloc, StoriesState>(
      builder: (context, storiesState) {
        if (storiesState is StoriesLoaded && storiesState.stories.isNotEmpty) {
          return const SliverAppBar(
            pinned: false,
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(80),
              child: StoriesView(),
            ),
          );
        } else {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
      },
    );
  }

  Widget _buildPageView(ScheduleState state) {
    return EventsPageView(
      controller: _pageController,
      itemBuilder: (context, index) {
        final day = Calendar.firstCalendarDay.add(Duration(days: index));
        final lessonsForDay = Calendar.getSchedulePartsByDay(
          schedule: state.selectedSchedule?.schedule ?? [],
          day: day,
        );

        final holiday = lessonsForDay.firstWhereOrNull(
          (element) => element is HolidaySchedulePart,
        );

        if (holiday != null) {
          return HolidayPage(title: (holiday as HolidaySchedulePart).title);
        }

        if (day.weekday == DateTime.sunday) {
          return const HolidayPage(title: 'Выходной');
        }

        final lessonsByTime = groupBy<LessonSchedulePart, int>(
          lessonsForDay.whereType<LessonSchedulePart>().toList(),
          (lesson) => lesson.lessonBells.number,
        );

        return ListView.builder(
          shrinkWrap: true,
          itemCount: SchedulePage.maxLessonsPerDay,
          itemBuilder: (context, lessonIndex) {
            final lessons = lessonsByTime[lessonIndex + 1] ?? [];

            return lessons.isNotEmpty
                ? _buildLessonCard(lessons, lessons.first, day)
                : state.showEmptyLessons
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: EmptyLessonCard(lessonNumber: lessonIndex + 1),
                      )
                    : const SizedBox.shrink();
          },
        );
      },
    );
  }

  Widget _buildLessonCard(List<LessonSchedulePart> lessons, LessonSchedulePart lesson, DateTime day) {
    return lessons.length == 1
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: LessonCard(
              lesson: lesson,
              onTap: (lesson) {
                context.go('/schedule/details', extra: (lesson, day));
              },
            ),
          )
        : ExpandablePageView.builder(
            itemCount: lessons.length,
            itemBuilder: (context, index) {
              final currentLesson = lessons[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: LessonCard(
                  countInGroup: lessons.length,
                  indexInGroup: index,
                  lesson: currentLesson,
                  onTap: (lesson) {
                    context.go('/schedule/details', extra: (lesson, day));
                  },
                ),
              );
            },
          );
  }
}
