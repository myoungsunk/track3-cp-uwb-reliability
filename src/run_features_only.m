function results = run_features_only(sim_data, params)
% RUN_FEATURES_ONLY Run only feature extraction path for phase 1 v2.
if nargin < 2
    params = struct();
end

[feature_table, sim_data_out] = extract_features_batch(sim_data, params);

results = struct();
results.feature_table = feature_table;
results.sim_data = sim_data_out;
results.params = params;
results.timestamp = datetime('now');
end
