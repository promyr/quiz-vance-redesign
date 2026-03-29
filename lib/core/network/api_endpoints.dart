/// Constantes de todos os endpoints do backend Python/FastAPI.
abstract class ApiEndpoints {
  // Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String logout = '/auth/logout';
  static const String refreshToken = '/auth/refresh';
  static const String me = '/auth/me';
  static const String passwordResetRequest = '/auth/password-reset/request';
  static const String passwordResetConfirm = '/auth/password-reset/confirm';

  // Quiz
  static const String quizGenerate = '/quiz/generate';
  static const String quizSubmit = '/quiz/submit';
  static const String quizHistory = '/quiz/history';
  static const String quizClearSeenQuestions = '/quiz/seen-questions';

  // Flashcards
  static const String flashcardsDue = '/flashcards';
  static const String flashcardsReview = '/flashcards/review';
  static const String flashcardsCreate = '/flashcards/create';
  static const String flashcardsBulkSync = '/flashcards/sync';

  // Simulado
  static const String simuladoGenerate = '/simulado/generate';
  static const String simuladoSubmit = '/simulado/submit';
  static const String simuladoHistory = '/simulado/history';

  // Ranking
  static const String rankingWeekly = '/ranking/weekly';
  static const String rankingMonthly = '/ranking/monthly';
  static const String rankingGlobal = '/ranking/global';

  // Quiz dissertativo
  static const String quizOpenGenerate = '/quiz/open/generate';
  static const String quizOpenGrade = '/quiz/open/grade';

  // Plano de estudo
  static const String studyPlanGenerate = '/study-plan/generate';

  // Biblioteca
  static const String libraryGeneratePackage = '/library/generate-package';

  // User
  static const String userStats = '/user/stats';
  static const String userProfile = '/user/profile';
  static const String userUpdateProfile = '/user/profile/update';
  static const String userAiConfig = '/user/ai-config';
  static const String userAchievements = '/user/achievements';
  static const String userAchievementsUnlock = '/user/achievements/unlock';

  // Billing
  static const String billingPlans = '/billing/plans';
  // billingSubscribe removido — o app usa billingCheckoutStart diretamente.
  static const String billingStatus = '/billing/status';
  static const String billingCheckoutStart = '/billing/checkout/start';
}
