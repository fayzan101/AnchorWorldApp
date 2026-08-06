import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class RequestsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RequestsAppBar({Key? key}) : super(key: key);

  void _goBack(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    if (Get.key.currentState?.canPop() == true) {
      Get.back();
      return;
    }
    Get.offAllNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppColors.brandGradient)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => _goBack(context),
      ),
      title: Text(
        'Connection requests',
        style: AppTextStyles.ui(size: 18, weight: FontWeight.w800, color: AppColors.white),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
