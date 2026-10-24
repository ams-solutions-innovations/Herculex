package com.ams.herculex.nutrition

data class FastingStageInfo(
    val hour: Int,
    val title: String,
    val category: String,
    val description: String,
)

object FastingStages {
    private val stages = mapOf(
        1 to FastingStageInfo(1, "Digestion & Absorption", "Digestion", "Body is digesting the last meal; blood glucose and insulin levels rise."),
        2 to FastingStageInfo(2, "Glycogen Storage", "Digestion", "Excess glucose is stored as glycogen in the liver and muscles."),
        3 to FastingStageInfo(3, "Peak Absorption", "Digestion", "Nutrients are distributed; blood glucose levels begin to stabilize."),
        4 to FastingStageInfo(4, "Early Post-Absorption", "Blood Sugar", "Stomach empties; insulin levels gradually decline."),
        5 to FastingStageInfo(5, "Digestive Rest", "Blood Sugar", "Digestive system calms down; insulin approaches baseline."),
        6 to FastingStageInfo(6, "Blood Sugar Stabilization", "Blood Sugar", "Insulin returns to baseline; liver begins tapping glycogen stores."),
        7 to FastingStageInfo(7, "Pancreatic Rest", "Blood Sugar", "Pancreas reduces insulin secretion; digestive tract is fully resting."),
        8 to FastingStageInfo(8, "Glucagon Activation", "Blood Sugar", "Glucagon begins releasing stored energy from the liver."),
        9 to FastingStageInfo(9, "Liver Glycogen Utilization", "Blood Sugar", "Liver steadily converts glycogen to fuel the brain and vital organs."),
        10 to FastingStageInfo(10, "Lipolysis Initiated", "Ketosis & Fat", "Body starts releasing fatty acids from fat cells for energy."),
        11 to FastingStageInfo(11, "Inflammation Reduction", "Regeneration", "Digestive tract is unburdened; inflammatory markers begin to fall."),
        12 to FastingStageInfo(12, "Metabolic Shift (Entering Ketosis)", "Ketosis & Fat", "Glycogen stores run low; body accelerates fat burning and ketone production."),
        13 to FastingStageInfo(13, "Accelerated Fat Breakdown", "Ketosis & Fat", "Body fat becomes the primary fuel source for muscles and organs."),
        14 to FastingStageInfo(14, "Enhanced Insulin Sensitivity", "Blood Sugar", "Cellular insulin sensitivity increases; glycemic control improves."),
        15 to FastingStageInfo(15, "Growth Hormone (HGH) Surge", "Regeneration", "Human growth hormone levels rise to protect lean muscle mass."),
        16 to FastingStageInfo(16, "Optimal Fat Burning (16:8)", "Ketosis & Fat", "Golden standard of intermittent fasting! Fat oxidation reaches peak efficiency."),
        17 to FastingStageInfo(17, "Cellular Cleanup Preparation", "Autophagy", "Cells identify damaged proteins for upcoming recycling."),
        18 to FastingStageInfo(18, "Autophagy Onset", "Autophagy", "Autophagy begins — body recycles damaged cells, debris, and misfolded proteins."),
        19 to FastingStageInfo(19, "Ketone Levels Rising", "Ketosis & Fat", "Blood ketone levels climb, providing steady fuel for body and mind."),
        20 to FastingStageInfo(20, "Mental Clarity & Focus", "Regeneration", "Ketones cross the blood-brain barrier, sharpening mental acuity and focus."),
        21 to FastingStageInfo(21, "Deep Autophagy", "Autophagy", "Cellular recycling accelerates in the liver, muscles, and kidneys."),
        22 to FastingStageInfo(22, "mTOR Pathway Downregulation", "Regeneration", "mTOR inhibition triggers cellular repair and longevity mechanisms."),
        23 to FastingStageInfo(23, "BDNF Surge", "Regeneration", "BDNF stimulates new neural connections and protects brain cells."),
        24 to FastingStageInfo(24, "24h Milestone: Full Autophagy", "Autophagy", "24 hours fasted! Glycogen is exhausted, autophagy is operating at full capacity."),
        25 to FastingStageInfo(25, "Mitochondrial Biogenesis", "Regeneration", "Cells stimulate the creation of fresh, more efficient mitochondria."),
        26 to FastingStageInfo(26, "Oxidative Stress Reduction", "Regeneration", "Potent endogenous antioxidant enzymes (glutathione) are activated."),
        27 to FastingStageInfo(27, "Visceral Fat Mobilization", "Ketosis & Fat", "Body selectively targets deep visceral fat around organs for energy."),
        28 to FastingStageInfo(28, "Neuroprotection", "Regeneration", "Ketone bodies shield neurons from oxidative stress and degeneration."),
        29 to FastingStageInfo(29, "Gut Barrier Strengthening", "Digestion", "Intestinal epithelial tight junctions strengthen, reducing gut permeability."),
        30 to FastingStageInfo(30, "Damaged Cell Clearance", "Autophagy", "Body accelerates clearance of non-functional cells (apoptosis)."),
        31 to FastingStageInfo(31, "Blood Pressure Normalization", "Regeneration", "Vascular tone relaxes and excess sodium excretion lowers blood pressure."),
        32 to FastingStageInfo(32, "Steady Gluconeogenesis", "Blood Sugar", "Liver produces exact baseline glucose from glycerol and amino acids."),
        33 to FastingStageInfo(33, "Deep Liver Detoxification", "Regeneration", "Liver enzymes operate at peak capacity processing metabolic residues."),
        34 to FastingStageInfo(34, "Catecholamine Optimization", "Regeneration", "Mild noradrenaline rise enhances alertness and maintains resting metabolic rate."),
        35 to FastingStageInfo(35, "Deep Ketogenesis", "Ketosis & Fat", "Ketosis reaches a sustained, high plateau for prolonged endurance."),
        36 to FastingStageInfo(36, "36h Milestone: Peak Autophagy & 300% HGH", "Autophagy", "36 hours fasted! Autophagy peaks and growth hormone surges up to 300%."),
        37 to FastingStageInfo(37, "DNA Repair Activation", "Regeneration", "DNA repair enzymes actively mend cellular mutations."),
        38 to FastingStageInfo(38, "Sirtuin (SIRT1) Activation", "Regeneration", "Longevity genes (sirtuins) promote youthful cellular function."),
        39 to FastingStageInfo(39, "Amyloid Plaque Clearance", "Autophagy", "Neuronal autophagy breaks down misfolded proteins in the brain."),
        40 to FastingStageInfo(40, "NF-kB Suppression", "Regeneration", "Body's primary systemic inflammatory cascade is strongly suppressed."),
        41 to FastingStageInfo(41, "Intestinal Stem Cell Renewal", "Digestion", "Intestinal stem cells initiate renewal of the gut mucosal layer."),
        42 to FastingStageInfo(42, "Metabolic Efficiency Peak", "Ketosis & Fat", "Energy production operates with minimal metabolic waste products."),
        43 to FastingStageInfo(43, "AGEs Reduction", "Regeneration", "Lower blood sugar curbs the formation of advanced glycation end-products."),
        44 to FastingStageInfo(44, "Senescent Cell Clearance", "Autophagy", "Body identifies and removes aged, inflammatory 'zombie' cells."),
        45 to FastingStageInfo(45, "Deep Cognitive Regeneration", "Regeneration", "Brain wave rhythms synchronize; stress levels and mental chatter decline."),
        46 to FastingStageInfo(46, "Hepatic Fat Clearance", "Ketosis & Fat", "Liver unburdens stored lipid deposits, restoring optimal function."),
        47 to FastingStageInfo(47, "Immune System Reset Prep", "Regeneration", "Aged white blood cells are dismantled for cellular recycling."),
        48 to FastingStageInfo(48, "48h Milestone: Immune System Reset & 500% HGH", "Regeneration", "48 hours fasted! White blood cells recycle and HGH increases up to 500%."),
        49 to FastingStageInfo(49, "Hematopoietic Stem Cell Trigger", "Regeneration", "Bone marrow initiates generation of fresh, undamaged immune cells."),
        50 to FastingStageInfo(50, "IGF-1 Downregulation", "Regeneration", "Reduced IGF-1 shifts cells from growth mode into deep self-defense."),
        51 to FastingStageInfo(51, "Mitophagy: Mitochondrial Clearance", "Autophagy", "Dysfunctional mitochondria are recycled to eliminate cellular stress."),
        52 to FastingStageInfo(52, "Complete Glycemic Neutrality", "Blood Sugar", "Zero blood sugar spikes; clean, predictable fuel delivered via ketones."),
        53 to FastingStageInfo(53, "Neurogenesis Stimulation", "Regeneration", "New neural connections form in the hippocampus."),
        54 to FastingStageInfo(54, "Cell Membrane Renewal", "Regeneration", "Phospholipids recycle into supple, resilient cell membranes."),
        55 to FastingStageInfo(55, "Vascular Inflammation Relief", "Regeneration", "Endothelial cells in blood vessel walls recover and soften."),
        56 to FastingStageInfo(56, "Deep Lipid Oxidation", "Ketosis & Fat", "Body oxidizes stubborn long-chain fatty acids for steady energy."),
        57 to FastingStageInfo(57, "Stress Resilience (HSP)", "Regeneration", "Heat shock proteins (HSPs) fortify cellular integrity against stress."),
        58 to FastingStageInfo(58, "Inflammatory Cytokine Suppression", "Regeneration", "IL-6 and TNF-alpha tissue levels decline to absolute baseline."),
        59 to FastingStageInfo(59, "Epigenetic Modulation", "Regeneration", "Epigenetic markers activate genes governing repair and longevity."),
        60 to FastingStageInfo(60, "Hormone Receptor Reset", "Regeneration", "Receptors for leptin, insulin, and thyroid hormones regain sensitivity."),
        61 to FastingStageInfo(61, "Oncogenic Signal Suppression", "Regeneration", "Downregulated growth pathways limit abnormal cell proliferation."),
        62 to FastingStageInfo(62, "Maximal ATP Efficiency", "Ketosis & Fat", "Mitochondria produce optimal clean ATP from ketones."),
        63 to FastingStageInfo(63, "Lymphatic System Cleansing", "Regeneration", "Lymphatic circulation efficiently clears waste from interstitial spaces."),
        64 to FastingStageInfo(64, "Cardioprotection", "Regeneration", "Reduced oxidative stress and vascular workload safeguard the heart."),
        65 to FastingStageInfo(65, "Collagen Remodeling", "Regeneration", "Autophagy clears degraded collagen, setting the stage for fresh synthesis."),
        66 to FastingStageInfo(66, "Peak BDNF Levels", "Regeneration", "Maximal stimulation of neural plasticity, memory, and cognitive resilience."),
        67 to FastingStageInfo(67, "Precursor Cell Proliferation", "Regeneration", "Tissue precursor cells stand ready to rebuild upon the first refeed."),
        68 to FastingStageInfo(68, "Minimal Inflammatory Biomarkers", "Regeneration", "hs-CRP and chronic inflammatory biomarkers reach their lowest levels."),
        69 to FastingStageInfo(69, "Autoimmune Response Balancing", "Regeneration", "Immune system quiets, reducing hyperactive autoimmune reactivity."),
        70 to FastingStageInfo(70, "Peak Stem Cell Regeneration", "Regeneration", "Stem cell activity peaks across digestive, immune, and dermal tissues."),
        71 to FastingStageInfo(71, "Refeed Preparation", "Digestion", "Digestive enzymes prepare for gentle, nutrient-dense nourishment."),
        72 to FastingStageInfo(72, "72h Milestone: Total Cellular Reset", "Regeneration", "72 hours fasted! Complete immune reset, finished autophagy cycle, and full rejuvenation.")
    )

    fun getStage(hour: Int): FastingStageInfo {
        val clamped = hour.coerceIn(1, 72)
        return stages[clamped] ?: FastingStageInfo(clamped, "Fasting Stage", "Regeneration", "Body continues its metabolic and cellular adaptation.")
    }

    /**
     * Resolves the English stage info from either an incoming message (e.g. "15h: ...")
     * or elapsed fasting duration in seconds. Always returns English copy.
     */
    fun resolve(stageMessage: String?, elapsedSeconds: Long): FastingStageInfo {
        // Try parsing hour from stageMessage first
        val parsedHour = stageMessage?.let { msg ->
            val match = Regex("""^(\d+)\s*h""", RegexOption.IGNORE_CASE).find(msg.trim())
            match?.groupValues?.getOrNull(1)?.toIntOrNull()
        }
        val hour = parsedHour ?: (elapsedSeconds / 3600L).toInt().coerceIn(1, 72)
        return getStage(hour)
    }

    /**
     * Clean English short format: "15h: Growth Hormone (HGH) Surge"
     */
    fun formatShortEnglish(stageMessage: String?, elapsedSeconds: Long): String {
        val info = resolve(stageMessage, elapsedSeconds)
        return "${info.hour}h: ${info.title}"
    }
}
