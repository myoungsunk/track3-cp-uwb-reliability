function test_merge_sim_data_guard
% TEST_MERGE_SIM_DATA_GUARD Validate sim_data merge consistency checks.
addpath('src');

params = struct('merge_t_axis_tol_ns', 1e-9, 'merge_fs_eff_tol_hz', 1e-3);

sim_a = make_sim_data(128, 2e9, 2);
sim_b = make_sim_data(128, 2e9, 3);
merged = merge_sim_data(sim_a, sim_b, params);
assert(size(merged.CIR_rx1, 1) == 5, 'Merged sample count mismatch.');

sim_bad_width = make_sim_data(64, 2e9, 1);
assert_error(@() merge_sim_data(sim_a, sim_bad_width, params), 'CIR_rx1 width mismatch');

sim_bad_t_axis = make_sim_data(128, 2e9, 1);
sim_bad_t_axis.t_axis = sim_bad_t_axis.t_axis + 1e-6;
assert_error(@() merge_sim_data(sim_a, sim_bad_t_axis, params), 't_axis mismatch');

sim_bad_fs = make_sim_data(128, 2e9, 1);
sim_bad_fs.fs_eff = sim_bad_fs.fs_eff + 1;
assert_error(@() merge_sim_data(sim_a, sim_bad_fs, params), 'fs_eff mismatch');

fprintf('test_merge_sim_data_guard passed.\n');
end

function sim_data = make_sim_data(n_tap, fs_hz, n_pos)
t_axis_ns = (0:n_tap-1)' / fs_hz * 1e9;

sim_data = struct();
sim_data.CIR_rx1 = complex(zeros(n_pos, n_tap));
sim_data.CIR_rx2 = complex(zeros(n_pos, n_tap));
sim_data.labels = true(n_pos, 1);
sim_data.x_coord_m = (1:n_pos)';
sim_data.y_coord_m = zeros(n_pos, 1);
sim_data.RSS_rx1 = zeros(n_pos, 1);
sim_data.RSS_rx2 = zeros(n_pos, 1);
sim_data.pol_type = repmat("CP", n_pos, 1);
sim_data.case_id = repmat("caseA", n_pos, 1);
sim_data.pos_id = uint32((1:n_pos)');
sim_data.t_axis = t_axis_ns;
sim_data.fs_eff = fs_hz;
end

function assert_error(fn_handle, expected_phrase)
failed = false;
try
    fn_handle();
catch exception_info
    failed = contains(exception_info.message, expected_phrase);
end
assert(failed, 'Expected merge guard error containing: %s', expected_phrase);
end
