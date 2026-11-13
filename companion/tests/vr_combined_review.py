"""Fail-closed reduction of the private review phases in one production combined session."""
from __future__ import annotations
from vr_interact_analyse import distance, vector


def expected_close_error(ui,records):
    """Only this fixture's counted, caught exception with a surviving menu is expected."""
    menu=next((r for r in records if r.get('kind')=='Q-review-menu-after-exit'),{})
    proof=all(menu.get(k) is True for k in ('valid','parent_world','opens')) and menu.get('caught')==1
    expected=[]
    unexpected=[]
    for line in ui['ui_errors']:
        if (proof and line.startswith('[nlvr] UI close hook: addons/nlvr_q_tests/lua/nlvr_q_tests/client.lua:') and
                line.endswith(': Q deliberately throwing close hook')):
            expected.append(line)
        else: unexpected.append(line)
    ui['expected_caught_errors'],ui['ui_errors']=expected,unexpected
    good=all(ui['checks'].values()) and not unexpected
    ui['success']=good and all(row['exists'] for row in ui['images'])
    ui['full_acceptance']=good and not ui['open']
    return ui


def analyse(records, physics):
    rows={r['kind']:r for r in records if str(r.get('kind','')).startswith('Q-review-')}
    samples=[r for r in physics if r.get('kind')=='review-sample']
    checks={}
    metrics={}
    overlay=rows.get('Q-review-overlays',{})
    checks['1_all_roles_visible']=(overlay.get('visible')==21 and overlay.get('modules_active') is True and
                                  overlay.get('budgets',{}).get('native_peak',1000)<=32 and
                                  overlay.get('budgets',{}).get('source_peak',1000)<=16 and
                                  all(r.get('visible') and r.get('handle') for r in overlay.get('roles',{}).values()))
    metrics['overlays_visible']=overlay.get('visible')
    metrics['overlay_budgets']=overlay.get('budgets')
    retired=rows.get('Q-review-retired',{})
    checks['1_hidden_native_retired']=bool(retired) and not retired.get('expired_native')
    walks=rows.get('Q-review-walk',{})
    checks['2_walk_sprint_shown_hands']=all(walks.get(k,{}).get('n',0)>=10 and walks[k]['max_error']<.8 and
                                           walks[k]['ghosts']==0 for k in ('walk','sprint'))
    metrics['hand_walk']=walks
    held_client=rows.get('Q-review-held-client',{})
    checks['2_client_held_lag_measured']=all(held_client.get(k,{}).get('n',0)>=10 for k in ('walk','sprint'))
    metrics['client_held_surface_lag']=held_client
    held=[r for r in samples if r.get('phase')=='hold' and r.get('held')]
    release=[r for r in samples if r.get('phase')=='hold' and r.get('time',0)>4.7 and r.get('throw')]
    checks['2_held_walk_release']=bool(held and release) and any(
        vector(r['player_velocity'])[0]>100 and distance(r['throw'],r['player_velocity'])<80 for r in release)
    metrics['held_lag_units_max']=max((r.get('hold_error',0) for r in held),default=None)
    setups={r.get('phase'):r for r in physics if r.get('kind')=='review-carry-setup'}
    checks['verify_carry_setup']=all(setups.get(k,{}).get('setup') is True and setups[k].get('control') is True
                                    for k in ('hold','blink','shift'))
    metrics['carry_setup']=setups
    mass=[r for r in samples if r.get('phase')=='masses' and r.get('time',0)>3.2]
    bodies=mass[-1].get('bodies',[]) if mass else []
    checks['4_stable_masses']=len(bodies)==5 and all(r['peak']<2000 and r['error']<.8 and r.get('settled') and
        (r.get('requested') is None or abs(r['mass']-r['requested'])<.0001) for r in bodies)
    metrics['springs']=bodies
    melee=[r for r in samples if r.get('phase')=='melee' and .1<r.get('time',0)<.3]
    checks['6_bounded_melee']=bool(melee) and all(isinstance(b.get('speed'),(int,float)) and b['speed']<160
        for r in melee for b in r.get('bodies',[])) and any(r.get('bodies') for r in melee)
    metrics['melee']=melee[:1]
    walls=[r for r in samples if r.get('phase')=='wall' and r.get('time',0)>.2]
    proxies=[r for r in walls if r.get('wall') and r.get('proxy')]
    guards=[r for r in physics if r.get('kind')=='review-wall-guard']
    jump=next((r for r in physics if r.get('kind')=='review-wall-discontinuity'),{})
    cases={r.get('case'):r for r in guards}
    checks['5_eye_side_proxy']=(len(proxies)>=10 and all(vector(r['proxy'])[0]<vector(r['wall'])[0] for r in proxies) and
        all(cases.get(k,{}).get('geometry_hit') and cases[k].get('eligible_without_wall') and cases[k].get('denied')
            for k in ('start','tracking','respawn','teleport')) and jump.get('before_far') is True)
    metrics['wall_guards']=guards
    for mode in ('blink','shift'):
        stage=next((r for r in physics if r.get('kind')=='review-stage' and r.get('name')==mode),{})
        tele=[r for r in samples if r.get('phase')==mode and r.get('teleport',{}).get('success') is True and
              r.get('teleport',{}).get('id')!=stage.get('previous_teleport') and r.get('time',0)>1.8]
        steps=[r for r in physics if r.get('kind')=='review-carry-step' and r.get('phase')==mode]
        drops=[r for r in physics if r.get('kind')=='review-carry-release' and r.get('phase')==mode and r.get('time',0)>.7]
        checks['7_'+mode+'_carry']=(bool(tele and steps) and not drops and
            all(r.get('held',0)>0 and r['held']==r.get('carried') for r in steps) and
            any(r.get('held',0)>0 and r['held']==r.get('carried') and r.get('hold_error',1000)<10 for r in tele))
        metrics[mode+'_carry']={'steps':len(steps),'drops':len(drops),'max_step_speed':max((r.get('speed',0) for r in steps),default=0),
                               'distance_units':sum(distance(r.get('delta'),(0,0,0)) for r in steps)}
        if mode=='shift': checks['7_shift_exceeds_old_proxy_cap']=metrics[mode+'_carry']['max_step_speed']>480
    negative={r.get('name'):r for r in physics if r.get('kind')=='review-negative-carry'}
    for kind in ('carry-wall','carry-constraint'):
        r=negative.get(kind,{})
        checks['verify_'+kind]=r.get('setup') is True and r.get('precondition') is True and r.get('released') is True and r.get('body_displacement',1000)<.01
    metrics['negative_carry']=negative
    stale=rows.get('Q-review-stale',{})
    checks['10_stale_follow_engine_fallback']=stale.get('travel',0)>40
    pause=rows.get('Q-review-pause',{})
    checks['3_paused_three_metre_room_step']=bool(pause) and pause.get('horizontal_error',1000)<.8
    pause_samples=[r for r in samples if r.get('phase')=='pause']
    resumed=(vector(pause_samples[-1]['feet'])[0]-vector(pause_samples[0]['feet'])[0]) if len(pause_samples)>2 else None
    checks['3_room_follow_resumed']=resumed is not None and abs(resumed-.4)<.1
    checks['3_sync_reach_after_resume']=bool(pause_samples) and all(r.get('sync_age',100) < .3 and r.get('proxy') for r in pause_samples)
    metrics['pause_resume_units']=resumed
    mesh=next((r for r in physics if r.get('kind')=='review-mesh-cost'),{})
    checks['11_mesh_cost']=mesh.get('triangles')==2000 and mesh.get('walking_speed')==200 and mesh.get('iterations',0)>=80 and mesh.get('after_ms',1000)<mesh.get('before_ms',0)
    metrics['mesh_cost']=mesh
    corpse=next((r for r in physics if r.get('kind')=='review-corpse-setting'),{})
    checks['12_corpse_setting_unchanged']=bool(corpse) and corpse.get('before')==corpse.get('after')
    menu=rows.get('Q-review-menu-after-exit',{})
    checks['9_13_wrist_exit_borrowed_menu']=all(menu.get(k) is True for k in ('valid','parent_world','opens')) and menu.get('caught')==1
    refresh=rows.get('Q-review-refresh',{})
    checks['14_cached_refresh']=refresh.get('frames',0)>100 and refresh.get('passes',0)<refresh.get('calls',0)
    metrics['refresh']=refresh
    cpu=rows.get('Q-review-cpu',{})
    checks['14_game_thread_cpu_measured']=all(cpu.get(k,{}).get('frames',0)>=10 for k in ('cached','uncached'))
    for row in cpu.values():
        if isinstance(row,dict) and row.get('frames'):
            row['cpu_ms_per_frame']=row['cpu_ms']/row['frames']
            row['cycles_per_frame']=row['cycles']/row['frames']
    metrics['paired_game_thread_cpu']=cpu
    healthy={r.get('label'):r for r in physics if r.get('kind')=='review-cpu-health'}
    checks['14_all_modules_during_cpu_control']=all(healthy.get(k,{}).get('modules_live') is True and
        healthy[k].get('proxies') is True and healthy[k].get('sync_age',100)<.3 for k in ('start','end'))
    metrics['cpu_health']=healthy
    return {'success':all(checks.values()),'checks':checks,'metrics':metrics,
            'note':'All modules together. Offline regressions retain 3 m pause/rebaseline, delayed climbing, light ragdoll bones, mesh caching and saturation. C natural frames remain a separate gate.'}
