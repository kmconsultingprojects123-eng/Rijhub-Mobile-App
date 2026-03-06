// Shared KYC step constants
const int KYC_TOTAL_STEPS = 4;
// Default seconds to show on the KYC verification success page before auto-redirect
const int KYC_SUCCESS_REDIRECT_SECONDS = 3;

/// Returns a fraction (0..1) representing progress for [stepIndex].
/// [stepIndex] is 1-based (1..KYC_TOTAL_STEPS).
double kycProgress(int stepIndex) {
  if (stepIndex <= 0) return 0.0;
  if (stepIndex >= KYC_TOTAL_STEPS) return 1.0;
  return stepIndex / KYC_TOTAL_STEPS;
}
