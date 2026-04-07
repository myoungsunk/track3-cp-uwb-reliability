function summary_table = run_4port_bc_sweep(project_root)
% RUN_4PORT_BC_SWEEP Run 4-case sweep:
%   scenario B/C x {material_class, geometric_class}
% and save summary CSV/MAT under results/.

if nargin < 1 || strlength(string(project_root)) == 0
    script_dir = fileparts(mfilename('fullpath'));
    project_root = fileparts(script_dir);
end

project_root = char(project_root);
script_dir = fullfile(project_root, 'src');
addpath(script_dir);

results_root = fullfile(project_root, 'results');
if ~exist(results_root, 'dir')
    mkdir(results_root);
end

run_defs = {
    'CP_caseB_4port.csv', 'caseB_4port_material',  'material_class',  'B', 'material';
    'CP_caseB_4port.csv', 'caseB_4port_geometric', 'geometric_class', 'B', 'geometric';
    'CP_caseC_4port.csv', 'caseC_4port_material',  'material_class',  'C', 'material';
    'CP_caseC_4port.csv', 'caseC_4port_geometric', 'geometric_class', 'C', 'geometric';
};

n_run = size(run_defs, 1);
rows = repmat(struct( ...
    'run_name', "", ...
    'scenario', "", ...
    'label_type', "", ...
    'status', "", ...
    'N', NaN, ...
    'LoS', NaN, ...
    'NLoS', NaN, ...
    'logistic_cv_auc', NaN, ...
    'logistic_eval_auc', NaN, ...
    'logistic_eval_accuracy', NaN, ...
    'logistic_ece', NaN, ...
    'best_model', "", ...
    'best_model_auc', NaN, ...
    'best_ablation', "", ...
    'best_ablation_auc', NaN, ...
    'output_dir', ""), n_run, 1);

for idx = 1:n_run
    input_csv = char(run_defs{idx, 1});
    run_name = char(run_defs{idx, 2});
    label_class_col = char(run_defs{idx, 3});
    scenario = string(run_defs{idx, 4});
    label_type = string(run_defs{idx, 5});
    output_dir = string(fullfile(results_root, run_name));

    rows(idx).run_name = string(run_name);
    rows(idx).scenario = scenario;
    rows(idx).label_type = label_type;
    rows(idx).output_dir = output_dir;

    if ~isfile(fullfile(project_root, input_csv))
        rows(idx).status = "missing_input";
        continue;
    end

    try
        outputs = run_casec_4port(input_csv, run_name, label_class_col);
    catch exception_info
        rows(idx).status = "failed";
        warning('[run_4port_bc_sweep] %s failed: %s', run_name, exception_info.message);
        continue;
    end

    feature_table = outputs.feature_table;
    valid_mask = feature_table.valid_flag & isfinite(feature_table.r_CP) & isfinite(feature_table.a_FP);
    labels_valid = logical(feature_table.label(valid_mask));

    rows(idx).N = height(feature_table);
    rows(idx).LoS = sum(feature_table.label == 1);
    rows(idx).NLoS = sum(feature_table.label == 0);

    if isempty(labels_valid)
        rows(idx).status = "empty_valid";
    elseif numel(unique(labels_valid)) < 2
        rows(idx).status = "single_class";
    elseif min(sum(labels_valid), sum(~labels_valid)) < get_param(outputs.params, 'nlos_min_count', 10)
        rows(idx).status = "minority_below_threshold";
    else
        rows(idx).status = "ok";
    end

    if ~isempty(fieldnames(outputs.model)) && isfield(outputs.model, 'cv_auc')
        rows(idx).logistic_cv_auc = outputs.model.cv_auc;
    end
    if ~isempty(fieldnames(outputs.results)) && isfield(outputs.results, 'roc')
        rows(idx).logistic_eval_auc = outputs.results.roc.auc;
        rows(idx).logistic_eval_accuracy = outputs.results.accuracy;
        rows(idx).logistic_ece = outputs.results.ece;
    end

    if istable(outputs.benchmark) && ~isempty(outputs.benchmark)
        [best_auc, best_idx] = max(outputs.benchmark.auc);
        rows(idx).best_model = string(outputs.benchmark.model_name(best_idx));
        rows(idx).best_model_auc = best_auc;
    end

    if istable(outputs.ablation) && ~isempty(outputs.ablation)
        [best_ab_auc, best_ab_idx] = max(outputs.ablation.auc);
        rows(idx).best_ablation = string(outputs.ablation.config(best_ab_idx));
        rows(idx).best_ablation_auc = best_ab_auc;
    end
end

summary_table = struct2table(rows);
csv_path = fullfile(results_root, 'summary_bc_4cases.csv');
mat_path = fullfile(results_root, 'summary_bc_4cases.mat');
writetable(summary_table, csv_path);
save(mat_path, 'summary_table');
end
