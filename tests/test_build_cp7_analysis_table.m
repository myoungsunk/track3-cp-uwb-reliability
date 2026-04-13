function test_build_cp7_analysis_table
% TEST_BUILD_CP7_ANALYSIS_TABLE Validate metadata propagation for CP7 diagnostics.
project_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_root, 'src'));

[analysis_table, metadata] = build_cp7_analysis_table(project_root, struct());

required_vars = { ...
    'sample_id', 'scenario', 'case_id', 'x_m', 'y_m', ...
    'label_geometric', 'label_material', ...
    'gamma_CP_rx1', 'gamma_CP_rx2', ...
    'a_FP_RHCP_rx1', 'a_FP_LHCP_rx1', ...
    'a_FP_RHCP_rx2', 'a_FP_LHCP_rx2'};

assert(all(ismember(required_vars, analysis_table.Properties.VariableNames)), 'Required CP7 columns are missing.');
assert(height(analysis_table) == 112, 'Expected 112 rows across scenario B/C.');
assert(all(isfinite(analysis_table.x_m)) && all(isfinite(analysis_table.y_m)), 'Coordinates must be finite.');
assert(all(ismember(["B", "C"], unique(analysis_table.scenario))), 'Scenarios B/C must be present.');
assert(sum(isfinite(analysis_table.label_geometric)) > 0, 'Geometric labels should be populated.');
assert(sum(isfinite(analysis_table.label_material)) > 0, 'Material labels should be populated.');
assert(metadata.unmatched_geometric == 0, 'Geometric label join should fully match.');
assert(metadata.unmatched_material == 0, 'Material label join should fully match.');

fprintf('test_build_cp7_analysis_table passed.\n');
end
