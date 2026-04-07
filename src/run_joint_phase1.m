function results = run_joint_phase1(sim_data_guide, sim_data_test, params)
% RUN_JOINT_PHASE1 Run integrated phase 1 v2 pipeline: features then localization.
if nargin < 3
    params = struct();
end

feature_results = run_features_only(sim_data_test, params);
localization_results = run_localization_only(sim_data_guide, feature_results.sim_data, params);

results = struct();
results.feature_table = feature_results.feature_table;
results.sim_data_test = feature_results.sim_data;
results.lut = localization_results.lut;
results.pos_est = localization_results.pos_est;
results.pos_info = localization_results.pos_info;
results.params = params;
results.timestamp = datetime('now');
end
