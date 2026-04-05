function test_run_joint_phase1_smoke
% TEST_RUN_JOINT_PHASE1_SMOKE Validate end-to-end wiring for phase 1 v2 APIs.

% Guide data for LUT.
ang = (-30:10:30)';
rssd = 0.2 * ang;
sim_guide = struct();
sim_guide.inc_ang = ang;
sim_guide.RSS_rx1 = rssd;
sim_guide.RSS_rx2 = zeros(size(rssd));

% Test sim_data with simple impulses.
n_pos = 3;
n_tap = 128;
fs_hz = 2e9;
t_axis_ns = (0:n_tap-1) / fs_hz * 1e9;

cir1 = complex(zeros(n_pos, n_tap));
cir2 = complex(zeros(n_pos, n_tap));
for i = 1:n_pos
    cir1(i, 20 + i) = 1.0;
    cir2(i, 20 + i) = 0.5;
end

sim_test = struct();
sim_test.CIR_rx1 = cir1;
sim_test.CIR_rx2 = cir2;
sim_test.t_axis = t_axis_ns;
sim_test.RSS_rx1 = [2; 0; -2];
sim_test.RSS_rx2 = [0; 0; 0];
sim_test.pos_id = uint32((1:n_pos)');
sim_test.labels = true(n_pos, 1);
sim_test.x_coord_m = [1; 2; 3];
sim_test.y_coord_m = [0; 0; 0];

params = struct();
params.fp_threshold_ratio = 0.2;
params.T_w = 2.0;
params.r_CP_clip = 1e4;
params.c0 = 299792458;
params.anchor_x_m = 0;
params.anchor_y_m = 0;
params.doa_reference_deg = 0;

results = run_joint_phase1(sim_guide, sim_test, params);

assert(isfield(results, 'feature_table') && istable(results.feature_table), 'feature_table missing.');
assert(isfield(results, 'lut') && isstruct(results.lut), 'lut missing.');
assert(isfield(results, 'pos_est') && istable(results.pos_est), 'pos_est missing.');
assert(height(results.feature_table) == n_pos, 'feature_table row count mismatch.');
assert(height(results.pos_est) == n_pos, 'pos_est row count mismatch.');

fprintf('test_run_joint_phase1_smoke passed.\n');
end
