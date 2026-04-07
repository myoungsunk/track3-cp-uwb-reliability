function test_rssd_lut
% TEST_RSSD_LUT Validate LUT inverse mapping accuracy and ambiguity flagging.

params = struct();
params.rssd_interp_method = 'pchip';
params.lut_ang_step = 0.05;

% 1) Linear RSSD curve: inverse error should be < 0.1 deg.
ang = (-40:5:40)';
rssd = 0.3 * ang + 2.0;
sim_guide_lin = struct();
sim_guide_lin.inc_ang = ang;
sim_guide_lin.RSS_rx1 = rssd;
sim_guide_lin.RSS_rx2 = zeros(size(rssd));

lut_lin = build_rssd_lut(sim_guide_lin, params);
true_ang = [ -27.5; -5.0; 12.5; 31.0 ];
meas_rssd = 0.3 * true_ang + 2.0;
[doa_lin, info_lin] = estimate_doa_rssd(meas_rssd, lut_lin, struct('doa_candidate_tol_db', 1e-6));

max_err = max(abs(doa_lin - true_ang));
assert(max_err < 0.1, 'Linear LUT inverse error must be < 0.1 deg.');
assert(~any(info_lin.ambiguity_flag), 'Linear monotonic LUT should not be ambiguous.');

% 2) Non-monotonic curve should trigger ambiguity for repeated RSSD values.
ang2 = (-90:10:90)';
rssd2 = sind(ang2);
sim_guide_nonmono = struct();
sim_guide_nonmono.inc_ang = ang2;
sim_guide_nonmono.RSS_rx1 = rssd2;
sim_guide_nonmono.RSS_rx2 = zeros(size(rssd2));

lut_nonmono = build_rssd_lut(sim_guide_nonmono, params);
[~, info_nonmono] = estimate_doa_rssd(0, lut_nonmono, struct('doa_candidate_tol_db', 0.02));
assert(any(info_nonmono.ambiguity_flag), 'Non-monotonic LUT should set ambiguity_flag=true for repeated RSSD.');

fprintf('test_rssd_lut passed.\n');
end
