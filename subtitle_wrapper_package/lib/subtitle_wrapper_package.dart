library subtitle_wrapper_package;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:subtitle_wrapper_package/bloc/subtitle/subtitle_bloc.dart';
import 'package:subtitle_wrapper_package/data/models/subtitle.dart';
import 'package:subtitle_wrapper_package/data/models/style/subtitle_style.dart';
import 'package:subtitle_wrapper_package/data/repository/subtitle_repository.dart';
import 'package:subtitle_wrapper_package/subtitle_controller.dart';
import 'package:subtitle_wrapper_package/subtitle_text_view.dart';

class SubTitleWrapper extends StatelessWidget {
  SubTitleWrapper({
    Key key,
    @required this.videoChild,
    @required this.subtitleController,
    @required this.videoPlayerController,
    @required this.subtitleNotifier,
    @required this.contextSubtitle,
    @required this.focusNode,
    @required this.emptyStack,
    @required this.isCasting,
    @required this.fontSize,
    @required this.regexFilter,
    this.subtitleStyle = const SubtitleStyle(),
  }) : super(key: key);

  final Widget videoChild;
  final SubtitleController subtitleController;
  final VlcPlayerController videoPlayerController;
  final SubtitleStyle subtitleStyle;
  final ValueNotifier<Subtitle> subtitleNotifier;
  final ValueNotifier<Subtitle> contextSubtitle;
  final ValueNotifier<bool> isCasting;
  final FocusNode focusNode;
  final VoidCallback emptyStack;
  final ValueNotifier<double> fontSize;
  final ValueNotifier<String> regexFilter;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        videoChild,
        BlocProvider(
            create: (context) => SubtitleBloc(
                  videoPlayerController: videoPlayerController,
                  subtitleRepository: SubtitleDataRepository(
                    subtitleController: subtitleController,
                  ),
                  subtitleController: subtitleController,
                  subtitleNotifier: subtitleNotifier,
                )..add(
                    InitSubtitles(
                      subtitleController: subtitleController,
                    ),
                  ),
            child: rebuildableTextView()),
      ],
    );
  }

  Widget rebuildableTextView() {
    if (!subtitleController.showSubtitles) {
      return Container();
    }

    return ValueListenableBuilder<bool>(
        valueListenable: isCasting,
        builder: (BuildContext context, bool casting, Widget child) {
          if (!casting) {
            return Container(
              child: Positioned(
                top: subtitleStyle.position.top,
                bottom: subtitleStyle.position.bottom,
                left: subtitleStyle.position.left,
                right: subtitleStyle.position.right,
                child: SubtitleTextView(
                  videoPlayerController: videoPlayerController,
                  subtitleStyle: subtitleStyle,
                  widgetVisibility: subtitleController.widgetVisibility,
                  comprehensionSubtitle:
                      subtitleController.comprehensionSubtitle,
                  contextSubtitle: subtitleController.contextSubtitle,
                  focusNode: focusNode,
                  emptyStack: emptyStack,
                  fontSize: fontSize,
                  regexFilter: regexFilter,
                ),
              ),
            );
          } else {
            return Container(
              padding: EdgeInsets.only(
                  left: subtitleStyle.position.left,
                  right: subtitleStyle.position.right),
              child: Center(
                child: SubtitleTextView(
                  videoPlayerController: videoPlayerController,
                  subtitleStyle: subtitleStyle,
                  widgetVisibility: subtitleController.widgetVisibility,
                  comprehensionSubtitle:
                      subtitleController.comprehensionSubtitle,
                  contextSubtitle: subtitleController.contextSubtitle,
                  focusNode: focusNode,
                  emptyStack: emptyStack,
                  fontSize: fontSize,
                  regexFilter: regexFilter,
                ),
              ),
            );
          }
        });
  }
}
