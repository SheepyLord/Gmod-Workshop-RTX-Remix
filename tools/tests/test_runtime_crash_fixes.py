"""The runtime's 0xC0000005 fixes are in the committed patches (runtime patches 0091 and 0092, ADR 0216).

A static check of the patch files, no compiler: the pipeline handle read under the lock (graphics and compute), the
command list recycled before its waiters wake, frame generation's duplicate semaphore waits gone (0091, a port of
upstream dxvk-remix c1a891bf85), and the Reflex latency ping that no longer dispatches sent messages inside Present
(0092)."""
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[2]
PATCHES = REPO / 'runtime' / 'patches'
UPSTREAM = 'c1a891bf85dbda78cab979010089c5c9b4256a11'


def patch_text(number: int) -> str:
    found = sorted(PATCHES.glob(f'{number:04d}-*.patch'))
    if len(found) != 1:
        raise AssertionError(f'expected one runtime patch {number:04d}, found {[p.name for p in found]}')
    text = found[0].read_text(encoding='utf-8')
    # git format-patch's signature ("-- " and the git version) is not part of the last file's diff.
    return re.sub(r'\n-- \n[^\n]*\n*\Z', '\n', text)


def sides(text: str, path: str) -> tuple[str, str]:
    """The old and the new side of every hunk of one file in a patch, each joined into one text."""
    block = text.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]
    old, new = [], []
    for hunk in block.split('\n@@ ')[1:]:
        for line in hunk.split('\n')[1:]:
            if line.startswith('-'):
                old.append(line[1:])
            elif line.startswith('+'):
                new.append(line[1:])
            elif line.startswith(' ') or line == '':
                old.append(line[1:])
                new.append(line[1:])
    return '\n'.join(old), '\n'.join(new)


def message(text: str) -> str:
    return text.split('\n---\n', 1)[0]


class PipelineHandleTests(unittest.TestCase):
    """0091: the handle is copied while m_mutex is held, before a state-cache worker can reallocate m_pipelines."""

    def check_order(self, new: str, steps: list[str]):
        at = -1
        for step in steps:
            found = new.find(step, at + 1)
            self.assertGreater(found, at, f'{step!r} is not after the previous step in:\n{new}')
            at = found

    def test_graphics_reads_the_handle_under_the_lock(self):
        old, new = sides(patch_text(91), 'src/dxvk/dxvk_graphics.cpp')
        # The bug as the fork had it: the handle read through the instance pointer after the lock scope.
        self.assertIn('this->writePipelineStateToCache(state, renderPass->format());\n    return instance->pipeline();',
                      old)
        self.check_order(new, [
            'VkPipeline pipeline = VK_NULL_HANDLE;',
            '{ std::lock_guard<sync::Spinlock> lock(m_mutex);',
            'instance = this->createInstance(state, renderPass);',
            '      if (instance)\n        pipeline = instance->pipeline();\n    }',
            'this->writePipelineStateToCache(state, renderPass->format());',
            'return pipeline;',
        ])
        # The only read through the pointer left is the found instance's, inside the lock.
        self.assertEqual(new.count('instance->pipeline()'), 2)
        self.assertLess(new.index('return instance->pipeline();'), new.index('this->createInstance('))

    def test_compute_reads_the_handle_under_the_lock(self):
        old, new = sides(patch_text(91), 'src/dxvk/dxvk_compute.cpp')
        self.assertIn('    return instance->pipeline();\n  }', old)
        self.check_order(new, [
            'VkPipeline pipeline = VK_NULL_HANDLE;',
            '{ std::lock_guard<sync::Spinlock> lock(m_mutex);',
            'instance = this->createInstance(state);',
            '      if (instance)\n        pipeline = instance->pipeline();\n    }',
            'this->writePipelineStateToCache(state);',
            'return pipeline;',
        ])
        self.assertNotIn('    return instance->pipeline();\n  }', new)

    def test_the_patch_credits_upstream(self):
        text = message(patch_text(91))
        self.assertIn(UPSTREAM, text)
        self.assertIn('MIT', text)


class QueueAndFrameGenerationTests(unittest.TestCase):
    def test_a_command_list_is_recycled_before_its_waiters_wake(self):
        old, new = sides(patch_text(91), 'src/dxvk/dxvk_queue.cpp')
        self.assertLess(old.index('m_finishCond.notify_all();'), old.index('entry.submit.cmdList->reset();'))
        steps = ['entry.submit.cmdList->reset();', 'm_device->recycleCommandList(entry.submit.cmdList);',
                 'm_pending -= 1;', 'm_finishCond.notify_all();']
        positions = [new.index(step) for step in steps]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(new.count('entry.submit.cmdList->reset();'), 1)

    def test_frame_generation_waits_once_on_the_acquire_semaphore(self):
        text = patch_text(91)
        block = text.split('diff --git a/src/dxvk/rtx_render/rtx_dlfg.cpp b/src/dxvk/rtx_render/rtx_dlfg.cpp\n', 1)[1]
        removed = [line for line in block.split('\n') if line.startswith('-') and not line.startswith('---')]
        added = [line for line in block.split('\n') if line.startswith('+') and not line.startswith('+++')]
        self.assertEqual(removed, ['-        commandList->addWaitSemaphore(renderedSwapchainImage.sync.acquire);'] * 2)
        self.assertEqual(added, [])


class LatencyPingTests(unittest.TestCase):
    """0092: the PCL ping is peeked only while no sent message is pending, so none is dispatched inside Present."""

    def test_the_peek_waits_out_a_sent_message(self):
        old, new = sides(patch_text(92), 'src/dxvk/rtx_render/rtx_reflex.cpp')
        self.assertIn('g_PCLStatsWindowMessage, g_PCLStatsWindowMessage, PM_REMOVE)) {', old)
        self.assertNotIn('GetQueueStatus', old)
        # Nothing posted, nothing to peek; a sent message pending, no peek; the peek itself posted messages only.
        self.assertRegex(new, r'GetQueueStatus\(QS_ALLPOSTMESSAGE\)\) & QS_ALLPOSTMESSAGE\) == 0\) \{\s*return;')
        self.assertIn('(HIWORD(::GetQueueStatus(QS_SENDMESSAGE)) & QS_SENDMESSAGE) != 0', new)
        self.assertRegex(new, r'while \(!sentMessagePending\(\) &&\s*PeekMessage\(&msg, kCurrentThreadId, '
                              r'g_PCLStatsWindowMessage, g_PCLStatsWindowMessage, PM_REMOVE \| PM_QS_POSTMESSAGE\)\)')
        # No other PeekMessage call is added.
        self.assertEqual(new.count('PeekMessage('), 1)

    def test_the_patch_says_why_the_flag_alone_is_not_enough(self):
        text = message(patch_text(92))
        self.assertIn('PM_QS_POSTMESSAGE alone does not prevent it', text)


if __name__ == '__main__':
    unittest.main()
