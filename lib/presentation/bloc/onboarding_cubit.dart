import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rtu_mirea_app/data/repositories/onboarding_repository.dart';
import 'package:rtu_mirea_app/domain/entities/onboarding_page.dart';
import 'package:rtu_mirea_app/domain/repositories/onboarding_repository.dart';
import 'package:rtu_mirea_app/domain/usecases/onboarding/get_page.dart';

/// [OnBoardingScreen] state management
/// Depends on page number
class OnBoardingCubit extends Cubit<OnBoardingPage> {
  final GetOnBoardingPages getPages;
  final List<OnBoardingPage> _pages = [];

  /// Initizalize first page and get info about all pages
  OnBoardingCubit({required this.getPages})
      : super(GetOnBoardingPages.firstPage) {
    _fillPages();
  }

  /// Fill pages array
  Future<void> _fillPages() async {
    var params = GetOnBoardingPagesParams(pagesCount: getPages.getPagesCount());
    _pages.addAll(await getPages.call(params));
  }

  /// Returns number of onboarding pages
  int getPagesCount() {
    return getPages.getPagesCount();
  }

  /// Get another page when swipe
  void swipe(int pageNum) => emit(_pages[pageNum]);
}