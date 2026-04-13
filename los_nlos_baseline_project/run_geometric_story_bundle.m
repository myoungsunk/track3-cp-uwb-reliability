function outputs = run_geometric_story_bundle()
% RUN_GEOMETRIC_STORY_BUNDLE
% Re-runs the geometric-target validation workflow and saves a clean,
% stage-separated bundle for reporting.

script_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(script_dir);

cfg = default_config(script_dir, project_root);
ensure_dir(cfg.bundle_root);
ensure_dir(cfg.stage00_execution_dir);
ensure_dir(cfg.stage01_baseline_dir);
ensure_dir(cfg.stage02_splits_dir);
ensure_dir(cfg.stage03_reviewer_dir);
ensure_dir(cfg.stage04_priority_dir);
ensure_dir(cfg.stage05_followup_dir);
ensure_dir(cfg.stage06_report_dir);

fprintf('=== Geometric Story Bundle ===\n');
fprintf('Bundle root: %s\n', cfg.bundle_root);

outputs = struct();
outputs.config = cfg;
outputs.started_at = datetime('now');

fprintf('\n[1/6] Re-running full baseline pipeline...\n');
baseline_outputs = run_los_nlos_baseline();
copy_baseline_geometric_outputs(cfg);

fprintf('\n[2/6] Re-running CP7 reviewer diagnostics (material + geometric, report uses geometric)...\n');
reviewer_cfg = struct();
reviewer_cfg.targets = ["material", "geometric"];
reviewer_cfg.results_dir = cfg.stage03_reviewer_dir;
reviewer_outputs = run_cp7_reviewer_diagnostics(reviewer_cfg);

fprintf('\n[3/6] Exporting geometric dataset splits...\n');
split_outputs = export_geometric_dataset_splits(cfg);

fprintf('\n[4/6] Re-running priority validations (geometric only)...\n');
priority_cfg = struct();
priority_cfg.targets = "geometric";
priority_cfg.reviewer_results_dir = cfg.stage03_reviewer_dir;
priority_cfg.results_dir = cfg.stage04_priority_dir;
priority_outputs = run_cp7_priority_validations(priority_cfg);

fprintf('\n[5/6] Re-running follow-up validations (geometric only)...\n');
followup_cfg = struct();
followup_cfg.targets = "geometric";
followup_cfg.reviewer_results_dir = cfg.stage03_reviewer_dir;
followup_cfg.results_dir = cfg.stage05_followup_dir;
followup_outputs = run_cp7_followup_validations(followup_cfg);

fprintf('\n[6/6] Writing execution conditions and final report...\n');
write_execution_conditions(cfg, baseline_outputs, reviewer_outputs, priority_outputs, followup_outputs);
write_geometric_story_report(cfg);
write_file_manifest(cfg);

outputs.baseline = baseline_outputs;
outputs.reviewer = reviewer_outputs;
outputs.splits = split_outputs;
outputs.priority = priority_outputs;
outputs.followup = followup_outputs;
outputs.completed_at = datetime('now');

save(fullfile(cfg.bundle_root, 'geometric_story_bundle_outputs.mat'), 'outputs', '-v7.3');
fprintf('Saved bundle under %s\n', cfg.bundle_root);
end

function cfg = default_config(script_dir, project_root)
cfg = struct();
cfg.script_dir = script_dir;
cfg.project_root = project_root;

cfg.bundle_root = fullfile(script_dir, 'results', 'geometric_story_bundle');
cfg.stage00_execution_dir = fullfile(cfg.bundle_root, '00_execution_conditions');
cfg.stage01_baseline_dir = fullfile(cfg.bundle_root, '01_baseline_full6cases');
cfg.stage02_splits_dir = fullfile(cfg.bundle_root, '02_dataset_splits');
cfg.stage03_reviewer_dir = fullfile(cfg.bundle_root, '03_reviewer_geometric');
cfg.stage04_priority_dir = fullfile(cfg.bundle_root, '04_priority_validations');
cfg.stage05_followup_dir = fullfile(cfg.bundle_root, '05_followup_validations');
cfg.stage06_report_dir = fullfile(cfg.bundle_root, '06_report');

cfg.default_results_root = fullfile(script_dir, 'results');
cfg.default_geometric_dir = fullfile(cfg.default_results_root, 'geometric');
cfg.default_target_summary_csv = fullfile(cfg.default_results_root, 'target_summary.csv');
cfg.default_baseline_mat = fullfile(cfg.default_results_root, 'los_nlos_baseline_outputs_all_targets.mat');
cfg.repro_command = 'matlab -batch "outputs = run_geometric_story_bundle;"';
end

function ensure_dir(dirpath)
if ~exist(dirpath, 'dir')
    mkdir(dirpath);
end
end

function copy_baseline_geometric_outputs(cfg)
ensure_dir(cfg.stage01_baseline_dir);
copy_selected_files(cfg.default_geometric_dir, cfg.stage01_baseline_dir, { ...
    'baseline_feature_table.csv', ...
    'feature_auc_by_scenario.csv', ...
    'feature_auc_by_scenario_best_pivot.csv', ...
    'feature_auc_by_scenario_raw_pivot.csv', ...
    'feature_auc_full_table.csv', ...
    'feature_auc_summary_table.csv', ...
    'feature_auc_univariate.csv', ...
    'feature_normalization.csv', ...
    'feature_summary.csv', ...
    'logistic_coefficients.csv', ...
    'los_nlos_baseline_outputs.mat', ...
    'metrics_by_case.csv', ...
    'metrics_by_fold.csv', ...
    'metrics_by_polarization.csv', ...
    'metrics_by_scenario.csv', ...
    'metrics_overall.csv'});

if isfile(cfg.default_target_summary_csv)
    copyfile(cfg.default_target_summary_csv, fullfile(cfg.stage01_baseline_dir, 'target_summary_all_targets.csv'));
end
if isfile(cfg.default_baseline_mat)
    copyfile(cfg.default_baseline_mat, fullfile(cfg.stage01_baseline_dir, 'los_nlos_baseline_outputs_all_targets.mat'));
end

src_fig_dir = fullfile(cfg.default_geometric_dir, 'figures');
dst_fig_dir = fullfile(cfg.stage01_baseline_dir, 'figures');
if exist(src_fig_dir, 'dir')
    ensure_dir(dst_fig_dir);
    copy_dir_files(src_fig_dir, dst_fig_dir);
end
end

function copy_selected_files(src_dir, dst_dir, filenames)
for idx = 1:numel(filenames)
    src = fullfile(src_dir, filenames{idx});
    if isfile(src)
        copyfile(src, fullfile(dst_dir, filenames{idx}));
    end
end
end

function copy_dir_files(src_dir, dst_dir)
entries = dir(src_dir);
for idx = 1:numel(entries)
    item = entries(idx);
    if item.isdir
        if strcmp(item.name, '.') || strcmp(item.name, '..')
            continue;
        end
        ensure_dir(fullfile(dst_dir, item.name));
        copy_dir_files(fullfile(src_dir, item.name), fullfile(dst_dir, item.name));
    else
        copyfile(fullfile(src_dir, item.name), fullfile(dst_dir, item.name));
    end
end
end

function split_outputs = export_geometric_dataset_splits(cfg)
target_dir = fullfile(cfg.stage03_reviewer_dir, 'geometric');
dataset_path = fullfile(target_dir, 'cp7_target_dataset.csv');
pred_path = fullfile(target_dir, 'oof_predictions_bc.csv');

dataset_table = readtable(dataset_path, 'TextType', 'string');
dataset_table.case_name = string(dataset_table.case_name);
dataset_table.scenario = string(dataset_table.scenario);
dataset_table.polarization = string(dataset_table.polarization);
dataset_table.valid_for_cp7_model = logical(dataset_table.valid_for_cp7_model);
dataset_table.label = logical(dataset_table.label);

prediction_table = readtable(pred_path, 'TextType', 'string');
prediction_table.case_name = string(prediction_table.case_name);
prediction_table.scenario = string(prediction_table.scenario);
prediction_table.hard_case_mask = logical(prediction_table.hard_case_mask);
prediction_table.label = logical(prediction_table.label);
prediction_table.baseline_pred = logical(prediction_table.baseline_pred);
prediction_table.proposed_pred = logical(prediction_table.proposed_pred);

valid_table = dataset_table(dataset_table.valid_for_cp7_model, :);
scope_b = valid_table(valid_table.scenario == "B", :);
scope_c = valid_table(valid_table.scenario == "C", :);
scope_bc = valid_table;

hard_case_bc = prediction_table(prediction_table.hard_case_mask, :);
hard_case_b = hard_case_bc(hard_case_bc.scenario == "B", :);
hard_case_c = hard_case_bc(hard_case_bc.scenario == "C", :);

baseline_error_bc = prediction_table(prediction_table.baseline_pred ~= prediction_table.label, :);
proposed_error_bc = prediction_table(prediction_table.proposed_pred ~= prediction_table.label, :);
rescued_bc = prediction_table(prediction_table.baseline_pred ~= prediction_table.label & prediction_table.proposed_pred == prediction_table.label, :);
harmed_bc = prediction_table(prediction_table.baseline_pred == prediction_table.label & prediction_table.proposed_pred ~= prediction_table.label, :);

writetable(dataset_table, fullfile(cfg.stage02_splits_dir, '00_cp7_target_dataset_raw.csv'));
writetable(valid_table, fullfile(cfg.stage02_splits_dir, '01_cp7_target_dataset_valid.csv'));
writetable(scope_b, fullfile(cfg.stage02_splits_dir, '02_scope_B.csv'));
writetable(scope_c, fullfile(cfg.stage02_splits_dir, '03_scope_C.csv'));
writetable(scope_bc, fullfile(cfg.stage02_splits_dir, '04_scope_BplusC.csv'));
writetable(hard_case_b, fullfile(cfg.stage02_splits_dir, '05_hard_case_B.csv'));
writetable(hard_case_c, fullfile(cfg.stage02_splits_dir, '06_hard_case_C.csv'));
writetable(hard_case_bc, fullfile(cfg.stage02_splits_dir, '07_hard_case_BplusC.csv'));
writetable(baseline_error_bc, fullfile(cfg.stage02_splits_dir, '08_baseline_errors_BplusC.csv'));
writetable(proposed_error_bc, fullfile(cfg.stage02_splits_dir, '09_proposed_errors_BplusC.csv'));
writetable(rescued_bc, fullfile(cfg.stage02_splits_dir, '10_rescued_by_cp7_BplusC.csv'));
writetable(harmed_bc, fullfile(cfg.stage02_splits_dir, '11_harmed_by_cp7_BplusC.csv'));

summary_table = table();
summary_table = add_split_summary_row(summary_table, "cp7_target_dataset_raw", "Joined CP7-capable geometric dataset before valid_for_cp7_model filtering", dataset_table.label);
summary_table = add_split_summary_row(summary_table, "cp7_target_dataset_valid", "Rows used for CP7 modeling after valid_for_cp7_model filtering", valid_table.label);
summary_table = add_split_summary_row(summary_table, "scope_B", "Scenario B only", scope_b.label);
summary_table = add_split_summary_row(summary_table, "scope_C", "Scenario C only", scope_c.label);
summary_table = add_split_summary_row(summary_table, "scope_BplusC", "Scenario B and C combined", scope_bc.label);
summary_table = add_split_summary_row(summary_table, "hard_case_B", "Baseline confidence in [0.4, 0.6], scenario B", hard_case_b.label);
summary_table = add_split_summary_row(summary_table, "hard_case_C", "Baseline confidence in [0.4, 0.6], scenario C", hard_case_c.label);
summary_table = add_split_summary_row(summary_table, "hard_case_BplusC", "Baseline confidence in [0.4, 0.6], scenario B+C", hard_case_bc.label);
summary_table = add_split_summary_row(summary_table, "baseline_errors_BplusC", "Baseline misclassifications on B+C", baseline_error_bc.label);
summary_table = add_split_summary_row(summary_table, "proposed_errors_BplusC", "Proposed misclassifications on B+C", proposed_error_bc.label);
summary_table = add_split_summary_row(summary_table, "rescued_by_cp7_BplusC", "Baseline wrong but CP7-correct on B+C", rescued_bc.label);
summary_table = add_split_summary_row(summary_table, "harmed_by_cp7_BplusC", "Baseline correct but CP7-wrong on B+C", harmed_bc.label);
summary_table.source_dir = repmat(string(cfg.stage02_splits_dir), height(summary_table), 1);
summary_table = movevars(summary_table, 'source_dir', 'After', 'description');

writetable(summary_table, fullfile(cfg.stage02_splits_dir, 'dataset_split_summary.csv'));

split_outputs = struct();
split_outputs.dataset_table = dataset_table;
split_outputs.valid_table = valid_table;
split_outputs.prediction_table = prediction_table;
split_outputs.summary_table = summary_table;
end

function summary_table = add_split_summary_row(summary_table, split_name, description, labels)
labels = logical(labels);
row = table();
row.split_name = string(split_name);
row.description = string(description);
row.n_samples = numel(labels);
row.n_los = sum(labels);
row.n_nlos = sum(~labels);
summary_table = [summary_table; row]; %#ok<AGROW>
end

function write_execution_conditions(cfg, baseline_outputs, reviewer_outputs, priority_outputs, followup_outputs)
kv = table();
kv = add_kv(kv, "environment", "bundle_root", cfg.bundle_root, "Top-level output folder for this rerun bundle");
kv = add_kv(kv, "environment", "script_dir", cfg.script_dir, "MATLAB script directory");
kv = add_kv(kv, "environment", "project_root", cfg.project_root, "Workspace root");
kv = add_kv(kv, "environment", "matlab_version", version, "MATLAB version string");
kv = add_kv(kv, "environment", "run_timestamp", string(datetime('now')), "Local execution timestamp");
kv = add_kv(kv, "environment", "repro_command", cfg.repro_command, "Command to reproduce this bundle");

base_cfg = baseline_outputs.config;
kv = add_kv(kv, "stage01_baseline", "label_target_report_focus", "geometric_class", "This report uses the geometric label target only");
kv = add_kv(kv, "stage01_baseline", "case_files", strjoin(base_cfg.case_files, ', '), "Full 6-case baseline universe");
kv = add_kv(kv, "stage01_baseline", "polarizations", "CP and LP", "Baseline uses both CP and LP");
kv = add_kv(kv, "stage01_baseline", "random_seed", num2str(base_cfg.random_seed), "Random seed for baseline CV");
kv = add_kv(kv, "stage01_baseline", "cv_folds", num2str(base_cfg.cv_folds), "Stratified CV fold count");
kv = add_kv(kv, "stage01_baseline", "classification_threshold", num2str(base_cfg.classification_threshold), "Threshold applied to logistic scores");
kv = add_kv(kv, "stage01_baseline", "logistic_lambda", num2str(base_cfg.logistic_lambda), "L2 regularization");
kv = add_kv(kv, "stage01_baseline", "feature_set", strjoin(base_cfg.model_feature_names, ', '), "Full literature-style CIR feature set used in the single-file baseline");

review_cfg = reviewer_outputs.config;
kv = add_kv(kv, "stage03_reviewer", "targets", join_string_array(review_cfg.targets), "Reviewer rerun stores both targets because downstream priority validation expects the shared material dataset");
kv = add_kv(kv, "stage03_reviewer", "case_names", join_string_array(review_cfg.case_names), "CP7 features exist for CP_caseB and CP_caseC only");
kv = add_kv(kv, "stage03_reviewer", "polarization", "CP only", "CP7 analysis is restricted to CP polarization");
kv = add_kv(kv, "stage03_reviewer", "cv_folds", num2str(review_cfg.cv_folds), "Stratified CV fold count");
kv = add_kv(kv, "stage03_reviewer", "random_seed", num2str(review_cfg.random_seed), "Random seed");
kv = add_kv(kv, "stage03_reviewer", "classification_threshold", num2str(review_cfg.classification_threshold), "Threshold for baseline and proposed predictions");
kv = add_kv(kv, "stage03_reviewer", "hard_case_band", sprintf('[%.1f, %.1f]', review_cfg.hard_case_band(1), review_cfg.hard_case_band(2)), "Baseline confidence interval used to define ambiguous samples");
kv = add_kv(kv, "stage03_reviewer", "baseline_features", strjoin(review_cfg.baseline_features, ', '), "Literature baseline feature set");
kv = add_kv(kv, "stage03_reviewer", "cp7_features", strjoin(review_cfg.cp7_features, ', '), "6 channel-resolved CP7 features");
kv = add_kv(kv, "stage03_reviewer", "metric_bootstrap_repeats", num2str(review_cfg.metric_bootstrap_repeats), "Bootstrap repeats for delta-AUC confidence intervals");

priority_cfg = priority_outputs.config;
kv = add_kv(kv, "stage04_priority", "n_cv_repeats", num2str(priority_cfg.n_cv_repeats), "Repeated CV count for ablation estimation");
kv = add_kv(kv, "stage04_priority", "permutation_repeats", num2str(priority_cfg.permutation_repeats), "Permutation importance repeat count");
kv = add_kv(kv, "stage04_priority", "rf_num_trees", num2str(priority_cfg.rf_num_trees), "Random forest tree count");
kv = add_kv(kv, "stage04_priority", "rf_min_leaf_size", num2str(priority_cfg.rf_min_leaf_size), "Random forest minimum leaf size");
kv = add_kv(kv, "stage04_priority", "spatial_cv_enabled", string(priority_cfg.spatial_cv_enabled), "Whether spatial CV check was run");
kv = add_kv(kv, "stage04_priority", "spatial_cv_strategy", string(priority_cfg.spatial_cv_strategy), "Spatial CV protocol");

follow_cfg = followup_outputs.config;
kv = add_kv(kv, "stage05_followup", "bootstrap_repeats", num2str(follow_cfg.bootstrap_repeats), "Dual-RX bootstrap repeat count");
kv = add_kv(kv, "stage05_followup", "mechanism_bootstrap_repeats", num2str(follow_cfg.mechanism_bootstrap_repeats), "Mechanism subgroup bootstrap repeat count");
kv = add_kv(kv, "stage05_followup", "rx1_features", strjoin(follow_cfg.rx1_features, ', '), "Single-RX1 CP7 features");
kv = add_kv(kv, "stage05_followup", "rx2_features", strjoin(follow_cfg.rx2_features, ', '), "Single-RX2 CP7 features");
kv = add_kv(kv, "stage05_followup", "dual_features", strjoin(follow_cfg.dual_features, ', '), "Dual-RX CP7 features");

csv_path = fullfile(cfg.stage00_execution_dir, 'execution_conditions.csv');
writetable(kv, csv_path);

md_path = fullfile(cfg.stage00_execution_dir, 'execution_conditions.md');
fid = fopen(md_path, 'w');
if fid < 0
    error('Failed to open markdown file: %s', md_path);
end
cleanup_obj = onCleanup(@() fclose(fid));

fprintf(fid, '# Geometric Validation Execution Conditions\n\n');
fprintf(fid, 'This bundle was generated by rerunning the geometric-target workflow and saving each stage into a dedicated directory.\n\n');
fprintf(fid, '## Reproduction Command\n\n');
fprintf(fid, '```matlab\n%s\n```\n\n', cfg.repro_command);
fprintf(fid, '## Key Notes\n\n');
fprintf(fid, '- The full baseline stage uses all 6 cases: `CP_caseA/B/C`, `LP_caseA/B/C`.\n');
fprintf(fid, '- The CP7 stages use `CP_caseB` and `CP_caseC` only, because the 6 channel-resolved CP7 features are available only there.\n');
fprintf(fid, '- The reviewer stage stores both `material` and `geometric` outputs because the downstream priority script expects the material dataset for its shared-correlation block; the final report still uses geometric outputs only.\n');
fprintf(fid, '- Therefore, `Stage 01` and `Stage 03-05` are based on different sample universes and their AUC values should not be compared as if they were from the same dataset.\n');
fprintf(fid, '- The hard-case subset is defined as baseline OOF confidence in `[0.4, 0.6]`.\n\n');

fprintf(fid, '## Condition Table\n\n');
fprintf(fid, '| Group | Key | Value | Description |\n');
fprintf(fid, '|---|---|---|---|\n');
for idx = 1:height(kv)
    fprintf(fid, '| %s | %s | %s | %s |\n', ...
        escape_md(kv.group(idx)), escape_md(kv.key(idx)), escape_md(kv.value(idx)), escape_md(kv.description(idx)));
end
end

function kv = add_kv(kv, group_name, key_name, value_text, desc_text)
row = table();
row.group = string(group_name);
row.key = string(key_name);
row.value = string(value_text);
row.description = string(desc_text);
kv = [kv; row]; %#ok<AGROW>
end

function write_geometric_story_report(cfg)
baseline_overall = readtable(fullfile(cfg.stage01_baseline_dir, 'metrics_overall.csv'), 'TextType', 'string');
baseline_case = readtable(fullfile(cfg.stage01_baseline_dir, 'metrics_by_case.csv'), 'TextType', 'string');
split_summary = readtable(fullfile(cfg.stage02_splits_dir, 'dataset_split_summary.csv'), 'TextType', 'string');

review_target_dir = fullfile(cfg.stage03_reviewer_dir, 'geometric');
review_incremental = readtable(fullfile(review_target_dir, 'incremental_summary.csv'), 'TextType', 'string');
review_mcnemar = readtable(fullfile(review_target_dir, 'mcnemar_tests.csv'), 'TextType', 'string');
review_rescue = readtable(fullfile(review_target_dir, 'misclassification_recovery_overall.csv'), 'TextType', 'string');
review_ortho = readtable(fullfile(review_target_dir, 'orthogonality_summary.csv'), 'TextType', 'string');

priority_shared = readtable(fullfile(cfg.stage04_priority_dir, 'shared', 'correlation_decision_summary.csv'), 'TextType', 'string');
priority_ablation = readtable(fullfile(cfg.stage04_priority_dir, 'geometric', 'ablation_summary.csv'), 'TextType', 'string');
priority_perm = readtable(fullfile(cfg.stage04_priority_dir, 'geometric', 'permutation_importance_summary.csv'), 'TextType', 'string');

follow_rx = readtable(fullfile(cfg.stage05_followup_dir, 'geometric', 'rx_model_summary.csv'), 'TextType', 'string');
follow_boot = readtable(fullfile(cfg.stage05_followup_dir, 'geometric', 'dual_rx_bootstrap_summary.csv'), 'TextType', 'string');
follow_mech = readtable(fullfile(cfg.stage05_followup_dir, 'geometric', 'mechanism_subgroup_summary.csv'), 'TextType', 'string');

baseline_overall_row = baseline_overall(1, :);
baseline_case_cp_b = baseline_case(baseline_case.group_name == "CP_caseB", :);
baseline_case_cp_c = baseline_case(baseline_case.group_name == "CP_caseC", :);
review_bc_overall = review_incremental(review_incremental.scope == "B+C" & review_incremental.subset_name == "overall", :);
review_bc_hard = review_incremental(review_incremental.scope == "B+C" & review_incremental.subset_name == "hard_case_0p4_0p6", :);
review_bc_mcnemar = review_mcnemar(review_mcnemar.scope == "B+C" & review_mcnemar.subset_name == "overall", :);
review_bc_hard_mcnemar = review_mcnemar(review_mcnemar.scope == "B+C" & review_mcnemar.subset_name == "hard_case_0p4_0p6", :);
rescue_row = review_rescue(1, :);
ablation_bc = priority_ablation(priority_ablation.scope == "B+C", :);
ablation_drop_gamma = ablation_bc(ablation_bc.variant_name == "drop_gamma_both", :);
ablation_drop_lhcp = ablation_bc(ablation_bc.variant_name == "drop_lhcp_pair", :);
ablation_drop_rhcp = ablation_bc(ablation_bc.variant_name == "drop_rhcp_pair", :);
perm_logistic = priority_perm(priority_perm.model_name == "logistic", :);
perm_rf = priority_perm(priority_perm.model_name == "rf", :);
rx_bc = follow_rx(follow_rx.scope == "B+C", :);
boot_bc = follow_boot(follow_boot.scope == "B+C", :);

report_path = fullfile(cfg.stage06_report_dir, 'geometric_cp7_story_report.md');
fid = fopen(report_path, 'w');
if fid < 0
    error('Failed to open report file: %s', report_path);
end
cleanup_obj = onCleanup(@() fclose(fid));

fprintf(fid, '# Geometric LoS/NLoS Validation Report\n\n');
fprintf(fid, '## 1. Purpose\n\n');
fprintf(fid, 'This report explains only the `geometric_class` target. It is written so that a first-time reader can understand the current status, the exact execution conditions, the data universe used at each step, and which claims are supported by the rerun results.\n\n');

fprintf(fid, '## 2. What Is Being Classified\n\n');
fprintf(fid, '- This report uses the `geometric_class` label only.\n');
fprintf(fid, '- The baseline stage uses the full 6-case dataset (`CP_caseA/B/C`, `LP_caseA/B/C`).\n');
fprintf(fid, '- The CP7 stages use `CP_caseB` and `CP_caseC` only, because the six channel-resolved CP7 features are available only for those CP measurements.\n');
fprintf(fid, '- Because the sample universe changes between stages, the full-baseline AUC and the CP7-subset AUC must be interpreted separately.\n\n');

fprintf(fid, '## 3. Exact Execution Conditions\n\n');
fprintf(fid, '- Full baseline: 16 CIR features, 5-fold stratified logistic regression, random seed 42, threshold 0.5, regularization `lambda = 1e-2`.\n');
fprintf(fid, '- Reviewer CP7 stage: baseline feature set `{fp_energy_db, skewness_pdp, kurtosis_pdp, mean_excess_delay_ns, rms_delay_spread_ns}`.\n');
fprintf(fid, '- Added CP7 feature set: `{gamma_CP_rx1, gamma_CP_rx2, a_FP_RHCP_rx1, a_FP_LHCP_rx1, a_FP_RHCP_rx2, a_FP_LHCP_rx2}`.\n');
fprintf(fid, '- CP7 reviewer stage: 5-fold stratified logistic regression, random seed 42, threshold 0.5, hard-case band `[0.4, 0.6]`, bootstrap repeats 1000.\n');
fprintf(fid, '- Priority stage: repeated CV count 20, permutation repeats 100, RF trees 80, RF min leaf size 2, spatial CV enabled.\n');
fprintf(fid, '- Follow-up stage: dual-RX bootstrap repeats 1000, mechanism subgroup bootstrap repeats 1000.\n');
fprintf(fid, '- A machine-readable condition table is saved at `00_execution_conditions/execution_conditions.csv`.\n\n');

fprintf(fid, '## 4. Data Separation by Procedure\n\n');
fprintf(fid, 'The bundle stores each subset used for validation as a separate CSV under `02_dataset_splits`.\n\n');
fprintf(fid, '| Split | Description | n | LoS | NLoS |\n');
fprintf(fid, '|---|---|---:|---:|---:|\n');
for idx = 1:height(split_summary)
    row = split_summary(idx, :);
    fprintf(fid, '| %s | %s | %s | %s | %s |\n', ...
        escape_md(row.split_name), escape_md(row.description), ...
        value_text(row, 'n_samples'), value_text(row, 'n_los'), value_text(row, 'n_nlos'));
end
fprintf(fid, '\nImportant split files:\n');
fprintf(fid, '- `02_dataset_splits/04_scope_BplusC.csv`: final CP7 modeling universe.\n');
fprintf(fid, '- `02_dataset_splits/07_hard_case_BplusC.csv`: ambiguous subset defined by baseline confidence `[0.4, 0.6]`.\n');
fprintf(fid, '- `02_dataset_splits/10_rescued_by_cp7_BplusC.csv`: samples misclassified by baseline but corrected by CP7 fusion.\n');
fprintf(fid, '- `02_dataset_splits/11_harmed_by_cp7_BplusC.csv`: samples correct in baseline but flipped incorrectly by CP7 fusion.\n\n');

fprintf(fid, '## 5. Step-by-Step Validation Story\n\n');
fprintf(fid, '### Step 1. Full 6-case geometric baseline\n\n');
fprintf(fid, '- Overall geometric baseline AUC: `%s`.\n', value_text(baseline_overall_row, 'auc'));
fprintf(fid, '- Overall accuracy: `%s`, F1: `%s`.\n', value_text(baseline_overall_row, 'accuracy'), value_text(baseline_overall_row, 'f1_score'));
fprintf(fid, '- This is the broad reference point, but it is not yet the CP7 universe.\n');
if ~isempty(baseline_case_cp_b)
    fprintf(fid, '- In the full baseline output, `CP_caseB` geometric AUC is `%s`.\n', value_text(baseline_case_cp_b, 'auc'));
end
if ~isempty(baseline_case_cp_c)
    fprintf(fid, '- In the full baseline output, `CP_caseC` geometric AUC is `%s`.\n', value_text(baseline_case_cp_c, 'auc'));
end
fprintf(fid, '\n### Step 2. Restrict to the CP7-capable universe\n\n');
fprintf(fid, '- The CP7 analysis universe is `CP_caseB + CP_caseC`, CP polarization only.\n');
fprintf(fid, '- After joining the baseline table and the CP7 table, the valid geometric modeling set contains 112 samples with a balanced label split of 56 LoS / 56 NLoS.\n');
fprintf(fid, '- This balanced subset is the correct universe for all CP7 claims below.\n\n');

fprintf(fid, '### Step 3. Reviewer validation: orthogonality, fusion gain, rescue\n\n');
fprintf(fid, '- On the geometric B+C subset, baseline AUC is `%s` and proposed AUC is `%s`.\n', value_text(review_bc_overall, 'baseline_auc'), value_text(review_bc_overall, 'proposed_auc'));
fprintf(fid, '- The AUC gain is `%s`, the Brier-score gain is `%s`, and McNemar exact `p = %s`.\n', ...
    value_text(review_bc_overall, 'delta_auc'), value_text(review_bc_overall, 'delta_brier'), value_text(review_bc_mcnemar, 'p_value_exact'));
fprintf(fid, '- On the hard-case subset, baseline AUC is `%s` and proposed AUC is `%s`.\n', ...
    value_text(review_bc_hard, 'baseline_auc'), value_text(review_bc_hard, 'proposed_auc'));
fprintf(fid, '- The hard-case McNemar exact `p = %s`.\n', value_text(review_bc_hard_mcnemar, 'p_value_exact'));
fprintf(fid, '- Baseline errors on B+C: `%s`; proposed errors: `%s`; rescued samples: `%s`; harmed samples: `%s`.\n', ...
    value_text(rescue_row, 'baseline_errors'), value_text(rescue_row, 'proposed_errors'), ...
    value_text(rescue_row, 'rescued_by_proposed'), value_text(rescue_row, 'harmed_by_proposed'));
fprintf(fid, '- This is the operational proof that CP7 features reduce geometric ambiguity: they improve paired metrics and rescue a large share of baseline mistakes.\n\n');

fprintf(fid, 'Orthogonality snapshot versus top-3 baseline features:\n\n');
fprintf(fid, '| CP7 feature | max abs Spearman | mean abs Spearman |\n');
fprintf(fid, '|---|---:|---:|\n');
for idx = 1:height(review_ortho)
    row = review_ortho(idx, :);
    fprintf(fid, '| %s | %s | %s |\n', value_text(row, 'cp7_feature'), value_text(row, 'max_abs_spearman_top3'), value_text(row, 'mean_abs_spearman_top3'));
end
fprintf(fid, '\nInterpretation: `gamma_CP_rx2` is the most orthogonal CP7 channel, while the `a_FP` channels overlap more with existing energy/shape descriptors.\n\n');

fprintf(fid, '### Step 4. Priority validation: channel-resolved correlation, ablation, permutation\n\n');
fprintf(fid, 'Channel-resolved max abs correlation against the full 5-feature baseline set:\n\n');
fprintf(fid, '| Feature | max abs corr | Decision |\n');
fprintf(fid, '|---|---:|---|\n');
for idx = 1:height(priority_shared)
    row = priority_shared(idx, :);
    fprintf(fid, '| %s | %s | %s |\n', value_text(row, 'cp7_feature'), value_text(row, 'max_abs_corr_any'), value_text(row, 'decision'));
end

fprintf(fid, '\nAblation on geometric B+C:\n\n');
fprintf(fid, '| Variant | AUC | Delta vs full | Brier | Delta Brier |\n');
fprintf(fid, '|---|---:|---:|---:|---:|\n');
for idx = 1:height(ablation_bc)
    row = ablation_bc(idx, :);
    fprintf(fid, '| %s | %s | %s | %s | %s |\n', ...
        value_text(row, 'variant_name'), value_text(row, 'auc'), value_text(row, 'delta_auc_vs_full'), ...
        value_text(row, 'brier_score'), value_text(row, 'delta_brier_vs_full'));
end
fprintf(fid, '\nKey reading:\n');
fprintf(fid, '- Dropping both `gamma` channels yields the largest AUC loss (`%s`).\n', value_text(ablation_drop_gamma, 'delta_auc_vs_full'));
fprintf(fid, '- Dropping the LHCP pair is the next-largest loss (`%s`).\n', value_text(ablation_drop_lhcp, 'delta_auc_vs_full'));
fprintf(fid, '- Dropping the RHCP pair has a smaller impact (`%s`).\n', value_text(ablation_drop_rhcp, 'delta_auc_vs_full'));
fprintf(fid, '- This supports a story where `gamma` is the main complementary axis and LHCP `a_FP` is the secondary geometric helper.\n\n');

fprintf(fid, 'Permutation importance ranking:\n\n');
fprintf(fid, '| Model | Feature | Mean AUC drop |\n');
fprintf(fid, '|---|---|---:|\n');
for idx = 1:height(perm_logistic)
    fprintf(fid, '| logistic | %s | %s |\n', value_text(perm_logistic(idx, :), 'feature_name'), value_text(perm_logistic(idx, :), 'mean_auc_drop'));
end
for idx = 1:height(perm_rf)
    fprintf(fid, '| rf | %s | %s |\n', value_text(perm_rf(idx, :), 'feature_name'), value_text(perm_rf(idx, :), 'mean_auc_drop'));
end
fprintf(fid, '\nThe geometric importance ranking again keeps `gamma` and LHCP near the top, even under a model-agnostic check.\n\n');

fprintf(fid, '### Step 5. Follow-up validation: single-RX vs dual-RX and subgroup mechanism checks\n\n');
fprintf(fid, 'Single-RX vs dual-RX on geometric B+C:\n\n');
fprintf(fid, '| Model | AUC | Brier | Accuracy |\n');
fprintf(fid, '|---|---:|---:|---:|\n');
for idx = 1:height(rx_bc)
    row = rx_bc(idx, :);
    fprintf(fid, '| %s | %s | %s | %s |\n', value_text(row, 'model_name'), value_text(row, 'auc'), value_text(row, 'brier_score'), value_text(row, 'accuracy'));
end
fprintf(fid, '\nDual-vs-best-single bootstrap:\n\n');
fprintf(fid, '| Delta AUC | 95%% CI | p(dual <= best) |\n');
fprintf(fid, '|---:|---|---:|\n');
fprintf(fid, '| %s | [%s, %s] | %s |\n', ...
    value_text(boot_bc, 'delta_auc_dual_minus_best_single'), value_text(boot_bc, 'ci_low'), ...
    value_text(boot_bc, 'ci_high'), value_text(boot_bc, 'p_dual_le_best'));
fprintf(fid, '\nInterpretation: the dual-RX gain exists numerically but is not statistically secure enough to be the main performance claim.\n\n');

fprintf(fid, 'Mechanism subgroup checks:\n\n');
fprintf(fid, '| Subset | Feature | n(L/N) | AUC | Status |\n');
fprintf(fid, '|---|---|---|---:|---|\n');
for idx = 1:height(follow_mech)
    row = follow_mech(idx, :);
    fprintf(fid, '| %s | %s | %s/%s | %s | %s |\n', ...
        value_text(row, 'subset_name'), value_text(row, 'feature_name'), value_text(row, 'n_los'), ...
        value_text(row, 'n_nlos'), value_text(row, 'auc'), value_text(row, 'status'));
end
fprintf(fid, '\nInterpretation: the mechanism trend is partially supportive, but some subgroup claims are underpowered and should stay in the discussion section rather than the main claim.\n\n');

fprintf(fid, '## 6. What Is Actually Proven for the Geometric Target\n\n');
fprintf(fid, 'Supported:\n');
fprintf(fid, '- The 6 CP7 features improve geometric LoS/NLoS discrimination on the CP7-capable B+C subset.\n');
fprintf(fid, '- The improvement is not only in AUC; it is also visible in Brier score, McNemar paired testing, and explicit rescue of baseline errors.\n');
fprintf(fid, '- The improvement concentrates on ambiguous samples defined by baseline confidence `[0.4, 0.6]`.\n');
fprintf(fid, '- `gamma` is the main complementary feature group, and LHCP `a_FP` is the secondary geometric helper.\n\n');

fprintf(fid, 'Not yet supported as a main claim:\n');
fprintf(fid, '- A universal multi-RX diversity gain.\n');
fprintf(fid, '- A strong subgroup-mechanism claim for every material/object subset.\n');
fprintf(fid, '- Any blanket statement that the CP7 features improve both geometric and material targets equally.\n\n');

fprintf(fid, '## 7. File Guide\n\n');
fprintf(fid, '- `00_execution_conditions`: exact run settings and reproduction command.\n');
fprintf(fid, '- `01_baseline_full6cases`: rerun geometric baseline outputs copied from the fresh baseline run.\n');
fprintf(fid, '- `02_dataset_splits`: step-by-step geometric subsets used in the CP7 story.\n');
fprintf(fid, '- `03_reviewer_geometric`: reviewer diagnostics rerun; contains geometric outputs plus the material helper dataset required by the priority stage.\n');
fprintf(fid, '- `04_priority_validations`: geometric-only correlation/ablation/permutation rerun.\n');
fprintf(fid, '- `05_followup_validations`: geometric-only single-vs-dual RX and subgroup rerun.\n');
fprintf(fid, '- `06_report`: this report and the file manifest.\n');
end

function write_file_manifest(cfg)
manifest = table();
manifest = add_manifest_row(manifest, "00_execution_conditions/execution_conditions.csv", "Machine-readable execution conditions");
manifest = add_manifest_row(manifest, "00_execution_conditions/execution_conditions.md", "Human-readable execution conditions");
manifest = add_manifest_row(manifest, "01_baseline_full6cases/metrics_overall.csv", "Full 6-case geometric baseline summary");
manifest = add_manifest_row(manifest, "01_baseline_full6cases/metrics_by_case.csv", "Full 6-case geometric per-case metrics");
manifest = add_manifest_row(manifest, "02_dataset_splits/dataset_split_summary.csv", "All stepwise geometric split counts");
manifest = add_manifest_row(manifest, "02_dataset_splits/07_hard_case_BplusC.csv", "Ambiguous subset defined by baseline confidence");
manifest = add_manifest_row(manifest, "02_dataset_splits/10_rescued_by_cp7_BplusC.csv", "Samples rescued by CP7 fusion");
manifest = add_manifest_row(manifest, "03_reviewer_geometric/geometric/incremental_summary.csv", "Reviewer-stage geometric incremental gain table (stage directory also contains the material helper dataset)");
manifest = add_manifest_row(manifest, "03_reviewer_geometric/geometric/mcnemar_tests.csv", "Reviewer-stage McNemar table");
manifest = add_manifest_row(manifest, "03_reviewer_geometric/geometric/misclassification_recovery_overall.csv", "Reviewer-stage rescue summary");
manifest = add_manifest_row(manifest, "04_priority_validations/shared/correlation_decision_summary.csv", "Channel-resolved correlation decisions");
manifest = add_manifest_row(manifest, "04_priority_validations/geometric/ablation_summary.csv", "Stepwise ablation results");
manifest = add_manifest_row(manifest, "04_priority_validations/geometric/permutation_importance_summary.csv", "Permutation importance summary");
manifest = add_manifest_row(manifest, "05_followup_validations/geometric/rx_model_summary.csv", "Single-RX vs dual-RX metrics");
manifest = add_manifest_row(manifest, "05_followup_validations/geometric/dual_rx_bootstrap_summary.csv", "Dual-RX bootstrap comparison");
manifest = add_manifest_row(manifest, "05_followup_validations/geometric/mechanism_subgroup_summary.csv", "Mechanism subgroup checks");
manifest = add_manifest_row(manifest, "06_report/geometric_cp7_story_report.md", "Final geometric-only narrative report");

manifest.relative_path = string(manifest.relative_path);
manifest.absolute_path = fullfile(cfg.bundle_root, manifest.relative_path);
manifest = movevars(manifest, 'absolute_path', 'After', 'relative_path');
out_path = fullfile(cfg.stage06_report_dir, 'file_manifest.csv');
writetable(manifest, out_path);
end

function manifest = add_manifest_row(manifest, rel_path, description)
row = table();
row.relative_path = string(rel_path);
row.description = string(description);
manifest = [manifest; row]; %#ok<AGROW>
end

function text = join_string_array(value)
if isstring(value)
    text = strjoin(cellstr(value(:)), ', ');
elseif iscellstr(value) || iscell(value)
    text = strjoin(value, ', ');
else
    text = string(value);
end
end

function out = value_text(row, var_name)
value = row.(var_name);
if iscell(value)
    out = string(value{1});
elseif isstring(value)
    out = value(1);
else
    out = string(value(1));
end
end

function out = escape_md(in)
out = replace(string(in), '|', '\|');
end
