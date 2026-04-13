function outputs = run_cp7_project
% RUN_CP7_PROJECT Re-run locked CP6 diagnostics and save outputs in this folder.
project_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(project_dir);
addpath(fullfile(repo_root, 'src'));

params = struct();
params.results_dir = project_dir;
outputs = run_cp7_feature_diagnostics('cp7_feature_diagnostics', params);
outputs.final_package = run_cp6_final_package();
end
