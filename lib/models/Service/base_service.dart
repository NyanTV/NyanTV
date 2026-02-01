import 'package:nyantv/controllers/service_handler/params.dart';
import 'package:nyantv/models/Media/media.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract class BaseService {
  RxList<Widget> homeWidgets(BuildContext context);
  RxList<Widget> animeWidgets(BuildContext context);
  Future<Media> fetchDetails(FetchDetailsParams params);
  Future<void> fetchHomePage();
  Future<List<Media>> search(SearchParams params);
}
