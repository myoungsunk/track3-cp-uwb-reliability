function results = run_localization_only(sim_data_guide, sim_data_test, params)
% RUN_LOCALIZATION_ONLY Run RSSD LUT, DoA, and position estimation path for phase 1 v2.
if nargin < 3
    params = struct();
end

lut = build_rssd_lut(sim_data_guide, params);
[pos_est, pos_info] = estimate_position(sim_data_test, lut, params);

results = struct();
results.lut = lut;
results.pos_est = pos_est;
results.pos_info = pos_info;
results.params = params;
results.timestamp = datetime('now');
end
