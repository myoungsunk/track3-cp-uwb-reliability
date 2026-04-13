function [analysis_table, metadata] = build_cp7_analysis_table(project_root, params)
% BUILD_CP7_ANALYSIS_TABLE Build B/C combined analysis table for locked 6-feature pipeline.
if nargin < 1 || strlength(string(project_root)) == 0
    script_dir = fileparts(mfilename('fullpath'));
    project_root = fileparts(script_dir);
end
if nargin < 2
    params = struct();
end

project_root = char(project_root);

params_local = default_cp7_build_params(project_root, params);
feature_names = { ...
    'gamma_CP_rx1', ...
    'gamma_CP_rx2', ...
    'a_FP_RHCP_rx1', ...
    'a_FP_LHCP_rx1', ...
    'a_FP_RHCP_rx2', ...
    'a_FP_LHCP_rx2'};

case_defs = { ...
    'CP_caseB_4port.csv', "B"; ...
    'CP_caseC_4port.csv', "C"};

analysis_table = table();
for idx_case = 1:size(case_defs, 1)
    csv_name = char(case_defs{idx_case, 1});
    scenario_tag = string(case_defs{idx_case, 2});
    csv_path = fullfile(project_root, csv_name);
    if ~isfile(csv_path)
        error('[build_cp7_analysis_table] Missing CSV: %s', csv_path);
    end

    freq_table = load_sparam_table(csv_path, params_local);
    sim_data = build_sim_data_from_table(freq_table, params_local);
    [feature_table, sim_data] = extract_features_batch(sim_data, params_local);

    n_row = min(height(feature_table), numel(sim_data.x_coord_m));
    feature_table = feature_table(1:n_row, :);

    block = table();
    block.scenario = repmat(scenario_tag, n_row, 1);
    block.case_id = string(sim_data.case_id(1:n_row));
    block.pos_id = double(feature_table.pos_id);
    block.x_m = double(sim_data.x_coord_m(1:n_row));
    block.y_m = double(sim_data.y_coord_m(1:n_row));
    block.valid_flag = logical(feature_table.valid_flag);
    block.gamma_CP_rx1 = log10(max(double(feature_table.r_CP_rx1), params_local.gamma_cp_floor));
    block.gamma_CP_rx2 = log10(max(double(feature_table.r_CP_rx2), params_local.gamma_cp_floor));
    block.a_FP_RHCP_rx1 = double(feature_table.a_FP_RHCP_rx1);
    block.a_FP_LHCP_rx1 = double(feature_table.a_FP_LHCP_rx1);
    block.a_FP_RHCP_rx2 = double(feature_table.a_FP_RHCP_rx2);
    block.a_FP_LHCP_rx2 = double(feature_table.a_FP_LHCP_rx2);
    block.label_geometric = nan(n_row, 1);
    block.label_material = nan(n_row, 1);
    block.label_geometric_matched = false(n_row, 1);
    block.label_material_matched = false(n_row, 1);

    analysis_table = [analysis_table; block]; %#ok<AGROW>
end

[label_geometric, matched_geometric, label_material, matched_material] = ...
    map_cp7_labels(analysis_table.scenario, analysis_table.x_m, analysis_table.y_m, params_local.label_csv);

analysis_table.label_geometric = label_geometric;
analysis_table.label_material = label_material;
analysis_table.label_geometric_matched = matched_geometric;
analysis_table.label_material_matched = matched_material;
analysis_table.all_features_valid = analysis_table.valid_flag & ...
    all(isfinite(analysis_table{:, feature_names}), 2);
analysis_table.sample_id = (1:height(analysis_table)).';
analysis_table = movevars(analysis_table, 'sample_id', 'Before', 1);

metadata = struct();
metadata.project_root = string(project_root);
metadata.label_csv = string(params_local.label_csv);
metadata.feature_names = feature_names;
metadata.case_files = case_defs(:, 1);
metadata.n_rows = height(analysis_table);
metadata.n_scenarios = numel(unique(analysis_table.scenario));
metadata.unmatched_geometric = sum(~matched_geometric);
metadata.unmatched_material = sum(~matched_material);
end

function params_local = default_cp7_build_params(project_root, params)
params_local = struct();
params_local.input_format = 'mp';
params_local.coord_unit = 'mm';
params_local.phase_unit = 'deg';
params_local.zeropad_factor = 4;
params_local.window_type = 'hanning';
params_local.freq_range_ghz = [3.1, 10.6];
params_local.fp_threshold_ratio = 0.2;
params_local.T_w = 2.0;
params_local.fp_window_ns = 2.0;
params_local.min_power_dbm = -120;
params_local.r_CP_clip = 1e4;
params_local.cp4_fp_reference = 'RHCP';
params_local.rcp_power_mode = 'WINDOW';
params_local.rcp_window_ns = 4.0;
params_local.gamma_cp_floor = max(get_param(params, 'gamma_cp_floor', 1e-6), eps);
params_local.random_seed = get_param(params, 'random_seed', 42);
params_local.cv_folds = get_param(params, 'cv_folds', 5);
params_local.normalize = true;
params_local.log10_rcp = false;
params_local.save_outputs = false;
params_local.data_role = 'test';
params_local.label_csv = char(get_param(params, 'label_csv', ...
    fullfile(project_root, 'LOS_NLOS_EXPORT_20260405', 'track23_all_scenarios_los_nlos.csv')));
params_local.label_col_class = 'geometric_class';
params_local.case_label_map = containers.Map({'caseA', 'caseB', 'caseC'}, {true, true, true});
end

function [label_geometric, matched_geometric, label_material, matched_material] = ...
    map_cp7_labels(scenario, x_m, y_m, label_csv)
if ~isfile(label_csv)
    error('[build_cp7_analysis_table] label_csv not found: %s', label_csv);
end

label_table = readtable(label_csv, 'VariableNamingRule', 'modify');
var_names = label_table.Properties.VariableNames;

col_scenario = char(find_column_name(var_names, {'scenario'}, true));
col_x = char(find_column_name(var_names, {'x_m', 'x', 'x_coord_m'}, true));
col_y = char(find_column_name(var_names, {'y_m', 'y', 'y_coord_m'}, true));
col_geometric = char(find_column_name(var_names, {'geometric_class'}, true));
col_material = char(find_column_name(var_names, {'material_class'}, true));

scenario_csv = upper(string(label_table.(col_scenario)));
x_csv = round(double(label_table.(col_x)), 3);
y_csv = round(double(label_table.(col_y)), 3);
geo_csv = upper(string(label_table.(col_geometric)));
mat_csv = upper(string(label_table.(col_material)));

geo_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
mat_map = containers.Map('KeyType', 'char', 'ValueType', 'double');

for idx = 1:height(label_table)
    key = compose_label_key(scenario_csv(idx), x_csv(idx), y_csv(idx));
    geo_val = class_string_to_binary(geo_csv(idx));
    mat_val = class_string_to_binary(mat_csv(idx));
    if ~isnan(geo_val) && ~isKey(geo_map, key)
        geo_map(key) = geo_val;
    end
    if ~isnan(mat_val) && ~isKey(mat_map, key)
        mat_map(key) = mat_val;
    end
end

n_row = numel(x_m);
label_geometric = nan(n_row, 1);
label_material = nan(n_row, 1);
matched_geometric = false(n_row, 1);
matched_material = false(n_row, 1);

scenario = upper(string(scenario(:)));
x_m = round(double(x_m(:)), 3);
y_m = round(double(y_m(:)), 3);

for idx = 1:n_row
    key = compose_label_key(scenario(idx), x_m(idx), y_m(idx));
    if isKey(geo_map, key)
        label_geometric(idx) = geo_map(key);
        matched_geometric(idx) = true;
    end
    if isKey(mat_map, key)
        label_material(idx) = mat_map(key);
        matched_material(idx) = true;
    end
end
end

function value = class_string_to_binary(class_name)
class_name = upper(char(string(class_name)));
if strcmp(class_name, 'LOS')
    value = 1;
elseif strcmp(class_name, 'NLOS')
    value = 0;
else
    value = NaN;
end
end

function key = compose_label_key(scenario, x_m, y_m)
key = sprintf('%s|%.3f|%.3f', upper(char(string(scenario))), double(x_m), double(y_m));
end
