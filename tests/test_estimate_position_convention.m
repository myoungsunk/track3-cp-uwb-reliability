function test_estimate_position_convention
% TEST_ESTIMATE_POSITION_CONVENTION Validate one-way range and +x/CCW angle convention.
addpath('src');

% Build guide LUT with monotonic linear RSSD-angle mapping.
sim_guide = struct();
sim_guide.inc_ang = (0:30:180)';
sim_guide.RSS_rx1 = 0.02 * sim_guide.inc_ang;
sim_guide.RSS_rx2 = zeros(size(sim_guide.inc_ang));
lut = build_rssd_lut(sim_guide, struct('lut_ang_step', 0.1, 'rssd_interp_method', 'pchip'));

% Build test CIR with known first-path taps.
n_pos = 2;
n_tap = 128;
dt_ns = 0.25;
t_axis_ns = (0:n_tap-1)' * dt_ns;

cir1 = complex(zeros(n_pos, n_tap));
cir2 = complex(zeros(n_pos, n_tap));
fp_idx = [21; 41];
for idx = 1:n_pos
    cir1(idx, fp_idx(idx)) = 1.0;
    cir2(idx, fp_idx(idx)) = 0.5;
end

sim_test = struct();
sim_test.CIR_rx1 = cir1;
sim_test.CIR_rx2 = cir2;
sim_test.t_axis = t_axis_ns;
sim_test.RSS_rx1 = [0.0; 1.8]; % maps to DoA [0 deg; 90 deg]
sim_test.RSS_rx2 = [0.0; 0.0];
sim_test.pos_id = uint32((1:n_pos)');

params = struct();
params.fp_threshold_ratio = 0.2;
params.c0 = 299792458;
params.anchor_x_m = 0;
params.anchor_y_m = 0;
params.doa_reference_deg = 0;

[pos_est, ~] = estimate_position(sim_test, lut, params);

expected_range = t_axis_ns(fp_idx) * 1e-9 * params.c0;
assert(max(abs(pos_est.range_est - expected_range)) < 1e-12, 'One-way range equation mismatch.');

assert(abs(pos_est.x_est(1) - expected_range(1)) < 1e-6, 'DoA=0 deg must map to +x axis.');
assert(abs(pos_est.y_est(1)) < 1e-6, 'DoA=0 deg must keep y near zero.');
assert(abs(pos_est.x_est(2)) < 1e-3, 'DoA=90 deg must keep x near zero.');
assert(abs(pos_est.y_est(2) - expected_range(2)) < 1e-3, 'DoA=90 deg must map to +y axis.');

fprintf('test_estimate_position_convention passed.\n');
end
