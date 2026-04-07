function sim_data = build_sim_data_from_table(freq_table, params)
% BUILD_SIM_DATA_FROM_TABLE Build CIR/RSS/labels sim_data from normalized frequency table.
if nargin < 2
    params = struct();
end
if ~istable(freq_table)
    error('[build_sim_data_from_table] freq_table must be a table.');
end

required_vars = {'x_coord_mm', 'y_coord_mm', 'freq_ghz', 'S21_rx1', 'S21_rx2', 'group_id'};
missing_vars = setdiff(required_vars, freq_table.Properties.VariableNames);
if ~isempty(missing_vars)
    error('[build_sim_data_from_table] Missing variables: %s', strjoin(missing_vars, ', '));
end

group_ids = unique(freq_table.group_id, 'stable');
n_group = numel(group_ids);
if n_group == 0
    error('[build_sim_data_from_table] Empty freq_table.');
end

freq_range_ghz = get_param(params, 'freq_range_ghz', [min(freq_table.freq_ghz), max(freq_table.freq_ghz)]);
if numel(freq_range_ghz) ~= 2 || any(~isfinite(freq_range_ghz))
    error('[build_sim_data_from_table] params.freq_range_ghz must be [f_min, f_max].');
end
freq_min = min(freq_range_ghz);
freq_max = max(freq_range_ghz);

window_type = lower(string(get_param(params, 'window_type', 'hanning')));
if window_type ~= "hanning"
    error('[build_sim_data_from_table] Only ''hanning'' window_type is supported by v2 spec.');
end

zeropad_factor = round(get_param(params, 'zeropad_factor', 4));
if ~isfinite(zeropad_factor) || zeropad_factor < 1
    error('[build_sim_data_from_table] params.zeropad_factor must be integer >= 1.');
end

cir_rx1_cell = cell(n_group, 1);
cir_rx2_cell = cell(n_group, 1);
x_mm = nan(n_group, 1);
y_mm = nan(n_group, 1);
inc_ang = nan(n_group, 1);
pol_type = strings(n_group, 1);
case_id = strings(n_group, 1);
valid_group = false(n_group, 1);

freq_ref = [];
df_hz = NaN;
n_freq_used = NaN;
n_fft = NaN;
window_vec = [];

has_inc = ismember('inc_ang_deg', freq_table.Properties.VariableNames);
has_pol = ismember('pol_type', freq_table.Properties.VariableNames);
has_case = ismember('case_id', freq_table.Properties.VariableNames);

for idx_group = 1:n_group
    group_mask = (freq_table.group_id == group_ids(idx_group));
    freq_vals = double(freq_table.freq_ghz(group_mask));
    s21_rx1_vals = freq_table.S21_rx1(group_mask);
    s21_rx2_vals = freq_table.S21_rx2(group_mask);

    [freq_vals, sort_idx] = sort(freq_vals, 'ascend');
    s21_rx1_vals = s21_rx1_vals(sort_idx);
    s21_rx2_vals = s21_rx2_vals(sort_idx);

    in_range = freq_vals >= freq_min & freq_vals <= freq_max;
    freq_vals = freq_vals(in_range);
    s21_rx1_vals = s21_rx1_vals(in_range);
    s21_rx2_vals = s21_rx2_vals(in_range);

    if numel(freq_vals) < 2
        continue;
    end

    [freq_unique, ~, unique_gid] = unique(freq_vals, 'stable');
    if numel(freq_unique) ~= numel(freq_vals)
        s21_rx1_vals = accumarray(unique_gid, s21_rx1_vals, [], @mean);
        s21_rx2_vals = accumarray(unique_gid, s21_rx2_vals, [], @mean);
        freq_vals = freq_unique;
    end

    if isempty(freq_ref)
        freq_ref = freq_vals(:);
        n_freq_used = numel(freq_ref);
        n_fft = n_freq_used * zeropad_factor;
        if n_fft < 2
            error('[build_sim_data_from_table] n_fft must be >= 2.');
        end
        window_vec = hanning(n_freq_used);
        df_hz = (freq_ref(2) - freq_ref(1)) * 1e9; % GHz -> Hz
        if ~isfinite(df_hz) || df_hz <= 0
            error('[build_sim_data_from_table] Invalid frequency spacing.');
        end
    else
        tol = 1e-9;
        if numel(freq_vals) ~= numel(freq_ref) || max(abs(freq_vals(:) - freq_ref)) > tol
            s21_rx1_vals = interp1(freq_vals, s21_rx1_vals, freq_ref, 'linear', 'extrap');
            s21_rx2_vals = interp1(freq_vals, s21_rx2_vals, freq_ref, 'linear', 'extrap');
            freq_vals = freq_ref;
        end
    end

    s21_win_rx1 = s21_rx1_vals(:) .* window_vec;
    s21_win_rx2 = s21_rx2_vals(:) .* window_vec;

    s21_pad_rx1 = [s21_win_rx1; zeros(n_fft - n_freq_used, 1)];
    s21_pad_rx2 = [s21_win_rx2; zeros(n_fft - n_freq_used, 1)];

    cir_rx1_cell{idx_group} = ifft(s21_pad_rx1, n_fft);
    cir_rx2_cell{idx_group} = ifft(s21_pad_rx2, n_fft);

    first_row = find(group_mask, 1, 'first');
    x_mm(idx_group) = double(freq_table.x_coord_mm(first_row));
    y_mm(idx_group) = double(freq_table.y_coord_mm(first_row));

    if has_inc
        inc_ang(idx_group) = double(freq_table.inc_ang_deg(first_row));
    end
    if has_pol
        pol_type(idx_group) = string(freq_table.pol_type(first_row));
    else
        pol_type(idx_group) = "UNKNOWN";
    end
    if has_case
        case_id(idx_group) = string(freq_table.case_id(first_row));
    else
        case_id(idx_group) = "UNKNOWN";
    end

    valid_group(idx_group) = true;

    if mod(idx_group, 100) == 0 || idx_group == n_group
        fprintf('[build_sim_data_from_table] %d/%d positions processed (%.1f%%)\n', ...
            idx_group, n_group, 100 * idx_group / n_group);
    end
end

if ~any(valid_group)
    error('[build_sim_data_from_table] No valid groups after freq filtering.');
end

cir_rx1 = cell2mat(cellfun(@(x) x(:).', cir_rx1_cell(valid_group), 'UniformOutput', false));
cir_rx2 = cell2mat(cellfun(@(x) x(:).', cir_rx2_cell(valid_group), 'UniformOutput', false));
x_mm = x_mm(valid_group);
y_mm = y_mm(valid_group);
inc_ang = inc_ang(valid_group);
pol_type = pol_type(valid_group);
case_id = case_id(valid_group);

n_pos = size(cir_rx1, 1);

dt_s = 1 / (n_fft * df_hz);
t_axis_ns = (0:n_fft-1) * dt_s * 1e9;

rss_rx1 = 10 * log10(sum(abs(cir_rx1).^2, 2));
rss_rx2 = 10 * log10(sum(abs(cir_rx2).^2, 2));

[labels, label_info] = assign_labels_for_positions(x_mm, y_mm, case_id, params);
if label_info.unmatched_count > 0
    warning('[build_sim_data_from_table] %d labels unmatched in CSV and filled by fallback/default.', label_info.unmatched_count);
end

sim_data = struct();
sim_data.CIR_rx1 = cir_rx1;
sim_data.CIR_rx2 = cir_rx2;
sim_data.t_axis = t_axis_ns;
sim_data.fs_eff = 1 / dt_s;
sim_data.pos_id = uint32((1:n_pos)');
sim_data.labels = labels;
sim_data.x_coord_m = x_mm / 1e3;
sim_data.y_coord_m = y_mm / 1e3;
sim_data.RSS_rx1 = rss_rx1;
sim_data.RSS_rx2 = rss_rx2;
sim_data.pol_type = pol_type;
sim_data.case_id = case_id;
sim_data.data_role = string(get_param(params, 'data_role', 'test'));

if has_inc && any(isfinite(inc_ang))
    sim_data.inc_ang = inc_ang;
end
end

function [labels, info] = assign_labels_for_positions(x_mm, y_mm, case_id, params)
n_pos = numel(x_mm);
labels = true(n_pos, 1);
matched = false(n_pos, 1);

label_csv = string(get_param(params, 'label_csv', ''));
if strlength(label_csv) > 0 && isfile(label_csv)
    label_table = readtable(char(label_csv), 'VariableNamingRule', 'modify');
    label_names = label_table.Properties.VariableNames;

    col_scenario = resolve_label_column(label_names, get_param(params, 'label_col_scenario', ''), {'scenario'});
    col_x = resolve_label_column(label_names, get_param(params, 'label_col_x', ''), {'x_m', 'x', 'x_coord_m'});
    col_y = resolve_label_column(label_names, get_param(params, 'label_col_y', ''), {'y_m', 'y', 'y_coord_m'});
    col_class = resolve_label_column(label_names, get_param(params, 'label_col_class', ''), {'material_class', 'class', 'label'});

    scenario_csv = upper(string(label_table.(col_scenario)));
    x_csv = round(double(label_table.(col_x)), 3);
    y_csv = round(double(label_table.(col_y)), 3);
    class_csv = upper(string(label_table.(col_class)));

    key_map = containers.Map('KeyType', 'char', 'ValueType', 'double');
    for idx = 1:height(label_table)
        key = compose_key(scenario_csv(idx), x_csv(idx), y_csv(idx));
        if class_csv(idx) == "LOS"
            value = 1;
        elseif class_csv(idx) == "NLOS"
            value = 0;
        else
            continue;
        end
        if ~isKey(key_map, key)
            key_map(key) = value;
        end
    end

    x_pos_m = round(x_mm / 1e3, 3);
    y_pos_m = round(y_mm / 1e3, 3);
    for idx = 1:n_pos
        scenario = case_to_scenario(case_id(idx));
        key = compose_key(scenario, x_pos_m(idx), y_pos_m(idx));
        if isKey(key_map, key)
            labels(idx) = logical(key_map(key));
            matched(idx) = true;
        end
    end
elseif strlength(label_csv) > 0
    warning('[build_sim_data_from_table] label_csv does not exist: %s', label_csv);
else
    warning('[build_sim_data_from_table] label_csv is not provided. Applying case_label_map fallback/default LoS.');
end

% NOTE: case_label_map is fallback-only in v2; primary label source is label_csv material_class join.
fallback_map = get_param(params, 'case_label_map', []);
for idx = 1:n_pos
    if matched(idx)
        continue;
    end

    fallback_value = fallback_label(case_id(idx), fallback_map);
    if ~isnan(fallback_value)
        labels(idx) = logical(fallback_value);
        matched(idx) = true;
    else
        labels(idx) = true;
    end
end

info = struct();
info.unmatched_count = sum(~matched);
end

function col_name = resolve_label_column(var_names, explicit_name, candidates)
explicit_name = string(explicit_name);
if strlength(explicit_name) > 0 && any(strcmp(var_names, explicit_name))
    col_name = char(explicit_name);
    return;
end
col_name = char(find_column_name(var_names, candidates, true));
end

function key = compose_key(scenario, x_m, y_m)
key = sprintf('%s|%.3f|%.3f', upper(char(string(scenario))), x_m, y_m);
end

function scenario = case_to_scenario(case_id)
case_id = lower(char(string(case_id)));
if startsWith(case_id, 'case') && numel(case_id) >= 5
    scenario = upper(string(case_id(5)));
else
    scenario = upper(string(case_id));
end
end

function value = fallback_label(case_id, map_obj)
value = NaN;
if isempty(map_obj)
    return;
end

key_primary = char(string(case_id));
key_lower = lower(key_primary);

if isa(map_obj, 'containers.Map')
    if isKey(map_obj, key_primary)
        value = double(map_obj(key_primary));
    elseif isKey(map_obj, key_lower)
        value = double(map_obj(key_lower));
    end
elseif isstruct(map_obj)
    if isfield(map_obj, key_primary)
        value = double(map_obj.(key_primary));
    elseif isfield(map_obj, key_lower)
        value = double(map_obj.(key_lower));
    end
end
end
