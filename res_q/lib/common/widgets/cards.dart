import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ReportCard extends StatelessWidget {
  final String id;
  final String title;
  final String? imageUrl;
  final String status;
  final String date;
  final String time;
  final int greenFlags;
  final int redFlags;
  final int comments;
  final VoidCallback? onTap;
  final VoidCallback? onCommentsTap;

  const ReportCard({
    super.key,
    required this.id,
    required this.title,
    this.imageUrl,
    required this.status,
    required this.date,
    required this.time,
    required this.greenFlags,
    required this.redFlags,
    required this.comments,
    this.onTap,
    this.onCommentsTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(title, style: AppText.subheading)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.appYellow),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(status, style: AppText.caption),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (imageUrl != null && imageUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    imageUrl!,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 8),
              Row(children: [Text('$date • $time', style: AppText.caption)]),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Badge(
                    icon: Icons.check_circle,
                    color: AppColors.appGreen,
                    label: '$greenFlags',
                  ),
                  const SizedBox(width: 12),
                  _Badge(
                    icon: Icons.cancel,
                    color: AppColors.appOffYellow,
                    label: '$redFlags',
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: onCommentsTap,
                    child: _Badge(
                      icon: Icons.comment,
                      color: AppColors.appRed,
                      label: '$comments',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommentCard extends StatelessWidget {
  final String id;
  final String author;
  final String text;
  final DateTime timestamp;
  final int greenFlags;
  final int redFlags;
  final VoidCallback? onUpvote;
  final VoidCallback? onDownvote;

  const CommentCard({
    super.key,
    required this.id,
    required this.author,
    required this.text,
    required this.timestamp,
    required this.greenFlags,
    required this.redFlags,
    this.onUpvote,
    this.onDownvote,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(author, style: AppText.subheading),
                Text(_formatDate(timestamp), style: AppText.caption),
              ],
            ),
            const SizedBox(height: 8),
            Text(text, style: AppText.body),
            const SizedBox(height: 12),
            Row(
              children: [
                _Badge(
                  icon: Icons.check_circle,
                  color: AppColors.appGreen,
                  label: '$greenFlags',
                  onTap: onUpvote,
                ),
                const SizedBox(width: 12),
                _Badge(
                  icon: Icons.cancel,
                  color: AppColors.appOffYellow,
                  label: '$redFlags',
                  onTap: onDownvote,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _Badge({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label, style: AppText.badge),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: onTap != null ? InkWell(onTap: onTap, child: content) : content,
    );
  }
}


