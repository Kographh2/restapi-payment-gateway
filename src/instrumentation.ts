let providerCapabilityReported=false;
// Next runs register before serving requests, including direct Next/Docker starts.
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const {config,ConfigurationError} = await import('./services/config');
    const {logDiagnostic}=await import('./services/diagnostics');
    let c;
    try{c=config();}catch(error){
      logDiagnostic('error',{event:'dependency_failure',subsystem:'configuration',failure:'invalid_configuration',configuration_fields:error instanceof ConfigurationError?error.issues.map(issue=>issue.split(':')[0]):undefined});
      throw error;
    }
    if (c.PAYMENT_ENV === 'production'&&!providerCapabilityReported) {
      providerCapabilityReported=true;
      logDiagnostic('info',{event:'capability_status',subsystem:'payments.provider',failure:'official_verification_not_onboarded_auth_independent'});
    }
  }
}
